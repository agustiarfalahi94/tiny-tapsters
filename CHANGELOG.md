# Changelog

All notable changes to Tiny Tapsters are documented here.
Format: **Added** · **Fixed** · **Changed** · **Removed** · **Improved**

---

## [1.8.0] — 2026-08-09

### Fixed
- **The cow's food was the wrong plant.** 🌱 is Unicode's *seedling* — a
  sprout, which read as "some plant" rather than grass. Cows now eat 🌾 hay.
- **The elephant's watermelon is gone.** 🍉 is a zoo treat, not a diet;
  elephants live on grass, leaves and bark, so it now eats 🌿 branches. (The
  peanut everyone pictures is a myth and was never a candidate.)

### Added
- **Foods are named once the child gets the match right** — the word appears
  under the solved slot, so a grown-up can say it aloud. Deliberately *after*
  the answer, never before: a caption up front would let a reading adult hand
  over the solution. The jigsaw, which shares this board widget, is unaffected.

### Changed
- **The two leaf foods never share a board.** 🍃 (giraffe) and 🌿 (elephant)
  are both green leaves, and with both on screen a toddler cannot tell which
  belongs to which — the puzzle stops being solvable by looking. Every game
  now drops one of the two.

### Notes
- Pairings audited for accuracy. Horse → 🍎 stays: an apple is a treat rather
  than a staple, but feeding one to a horse is a real, long-standing practice.
  Rabbit → 🥕 and mouse → 🧀 are both closer to cartoon lore than to diet
  (rabbits live on hay and greens, mice prefer grain) and stay anyway, because
  they are how a toddler already understands those animals.
- `flutter analyze`: 0 issues; 24/24 tests. Both new tests were confirmed to
  fail with their feature removed.

---

## [1.7.0] — 2026-08-09

### Changed
- **Every game reaches its celebration far sooner.** The pause between the
  last tap and the winner screen was 600–1450ms; it is now sized to the
  animation it is covering, and nothing more:

  | Game | Before | After |
  |---|---|---|
  | Jigsaw Puzzle | 600ms | **100ms** |
  | Animal Food | 600ms | **100ms** |
  | Bubble Pop | 600ms | **400ms** |
  | Find It! | 650ms | **350ms** |
  | Count the Animals! | 600ms | **350ms** |
  | Memory Match | 1450ms | **1150ms** |

  Jigsaw and Animal Food snap their last piece instantly, so their 600ms was
  pure dead air and went to 100ms. The rest are now exactly as long as the
  feedback the child is watching — the 400ms bubble burst, the 350ms tap
  tint, the 350ms card highlight — so the celebration lands the moment that
  animation ends rather than after it.

  Memory Match cannot reach 100ms without breaking the game: the 750ms
  compare window is what lets a toddler see *which* two emoji matched (and is
  the same window that shows a wrong pair before it flips back), so only the
  beat after the match resolves was cut, 700ms → 400ms.

  Count the Animals! shares one timer between "advance to the next round" and
  "show the win", so its rounds now turn over faster too.

### Notes
- `flutter analyze`: 0 issues; 22/22 tests. The Bubble Pop tests were
  restructured: the win delay now exactly equals the pop animation, so the
  old helper's 450ms-per-tap pump would have fired the win mid-loop. The
  round-completing tap is now the caller's, and the "extra tap was rejected"
  assertion counts pop-sparkles instead of relying on a clamped label.
  Re-verified that the test still fails when the `_roundComplete` guard is
  removed.

---

## [1.6.3] — 2026-08-09

### Fixed
- **Pollie lost almost everything a child said.** 1.6.1's "banking" turn —
  re-arming the mic after every recogniser endpoint and only sending once the
  child went quiet — was a bad trade. Each restart costs a few hundred
  milliseconds of dead air, and a child talking continuously loses most of
  their words into those gaps; *"i accidentally throw my toys in the washing
  machine and now it doesn't want to turn on"* arrived as **"want"**. Two
  restarts also raced each other, because `_relisten()` was called from both
  the final-result branch and the `done` status callback, so the loser threw
  "recognizer busy" and churned.
  There is now **one recogniser session per turn**. The pause tolerance is
  bought from `pauseFor` instead, which Android does honour.
- **A turn that ended any way except a final result sent nothing at all.**
  `_endTurn` sent `_heard`, which is only ever written on the one path that
  already sends — so tapping the mic to finish, the 45-second cap, and every
  speech error silently discarded the whole utterance. That last one is the
  common case, not an edge case: the Android plugin marks *every* error
  `permanent`, including the `no match` it raises after streaming perfectly
  good partial results. The turn now sends the full live transcript.
- **Bubble Pop counted pops after the round was already won.** `_pop()`
  guarded on `_won`, which is only set 600 ms later, so a bubble tapped during
  the celebration delay still incremented the counter and the header rendered
  **"Pop -1 more!"**. Completion is now recorded synchronously; the label and
  progress bar are clamped as a backstop.
- **Bubble Pop's celebration could appear over a fresh round.** The 600 ms win
  timer was never cancelled, so hitting 🔁 inside that window let it fire over
  the reset round. It is now a cancellable timer, cancelled on manual reset, on
  the next round, and on dispose.
- `onSoundLevelChange` could `setState` after dispose when leaving Pollie
  mid-listen; it now carries the same guard as its sibling callbacks.

### Changed
- The silence needed to end a turn is **3 seconds** (was 5) — 5 felt like a
  long wait before Pollie answered.

### Notes
- `flutter analyze`: 0 issues; 22/22 tests. The two new Bubble Pop tests were
  each confirmed to fail against the unfixed code before being accepted.
- Built with the `superpowers:subagent-driven-development` workflow: an
  implementer per task, a reviewer after each, and a whole-branch review at
  the end — which is what caught the empty-`_heard` regression above.

---

## [1.6.2] — 2026-08-09

### Fixed
- **Voice selection still did nothing after 1.6.1** — a second bad cast in the
  same method, hidden by the same bare `catch`. `getVoices` returns the raw
  platform-channel value (`List<Object?>` of `Map<Object?, Object?>`), and
  casting that to `List<Map<dynamic, dynamic>>` throws, because `Object?` is
  not a `Map`. The list is now rebuilt element by element. Confirmed on the
  Xiaomi 15 from Google TTS's own log: before the fix every utterance was
  `Synthesis request for locale eng-USA and name en-US-language` — the generic
  language default, proof `setVoice()` was never reaching the engine.
- The `catch` now logs why selection failed instead of swallowing it. Two
  separate bugs hid in that silence.

### Changed
- Pollie keeps the engine's default voice unless the chosen one has a real
  quality rating from Android — no point trading a working default for a
  voice nothing is known about.

### Notes
- `flutter analyze`: 0 issues; 20/20 tests (new: a guard asserting the old
  platform-channel cast throws, and that rebuilt maps still rank correctly).

---

## [1.6.1] — 2026-08-09

### Fixed
- **Pollie's voice was never actually chosen.** `_applyBestVoice` read each
  voice's quality with `(voice['quality'] as num?)`, but Android reports
  quality as a *word* (`"very high"`), so the cast threw on the first
  comparison, the surrounding `catch` swallowed it, and `setVoice()` was never
  reached. Pollie has always spoken with whatever voice the system defaulted
  to. Quality is now read from a string table, and voices are ranked by
  quality → exact locale → network (neural) → female, with eSpeak pushed last.
  The chosen voice is logged so it can be confirmed on a real device.
- **The microphone cut the child off mid-sentence.** Android's recogniser has
  two silence timers: the "definitely finished" one (exposed by the plugin as
  `pauseFor`, previously 2s) and a much shorter "possibly finished" one that
  `speech_to_text` never sets and cannot be configured. Ending the child's
  turn on either was far too aggressive for a toddler.

### Changed
- **A listening turn is now the app's, not the recogniser's.** Each session's
  words are banked and the mic is immediately re-armed; the turn ends — and
  the text is only then sent to Pollie — once the child has genuinely been
  quiet for 5 seconds. A turn is capped at 45s, and gives up after two
  sessions that heard nothing at all. Tapping the mic while it is live still
  means "I'm done" and sends what has been collected so far.
- The live transcript now shows everything banked this turn, not just the
  current fragment.
- **Pollie sounds less synthetic**: pitch 1.35 → 1.1 and rate 0.5 → 0.45.
  Pushing pitch that high is what made a mediocre voice sound robotic.

### Notes
- `flutter analyze`: 0 issues; 19/19 tests (new: voice ranking, including a
  regression test that fails against the old numeric cast; locale preference;
  empty and no-match voice lists).

---

## [1.6.0] — 2026-08-08

### Changed
- **The app is now Tiny Tapsters** (was "Our Toddlers' Journey") — new name
  across the launcher label, the home screen title, the window title, the
  README and this changelog. The old name was cut off by every launcher
  ("Our Toddlers'…"), was written from the parents' point of view rather than
  the child's, and promised a "journey" the app does not actually track.
- **Package renamed to `com.inkpebble.tiny_tapsters`** (was
  `com.lilianyoctoria.toddlers_journey`), moving to the same `inkpebble`
  developer prefix as the `random_recall` project. Android treats this as a
  new application: it installs alongside the old one instead of updating it,
  so the previous version must be uninstalled by hand. Done now, before any
  Play Store publish would have frozen the old identifier forever.
- **Dart package renamed** `toddlers_journey` → `tiny_tapsters`, and
  `pubspec.yaml` finally has a real description instead of the Flutter
  template's "A new Flutter project."
- Release APKs are now named `tiny-tapsters-vX.Y.Z.apk`.

### Added
- **Real launcher icon from the Tiny Tapsters artwork** — the mint badge with
  the tablet-holding baby, replacing the hand-drawn smiley. `assets/branding/`
  holds the master logo; it is build-time only and is not bundled into the APK.

### Improved
- **`tool/generate_icon.dart` rewritten** to derive icons from the artwork
  instead of drawing a design in code. Still pure Dart with no packages: it
  now includes a small PNG *decoder* (8-bit truecolour) alongside the existing
  encoder. It locates the badge, samples its mint fill, knocks the white page
  colour out of the rounded corners by flood fill (which preserves the white
  sparkles and eyes, since those are enclosed by ink), isolates the baby as
  the largest connected blob, and fits it to the adaptive-icon safe zone.

### Notes
- `flutter analyze`: 0 issues; 16/16 tests.

---

## [1.5.0] — 2026-08-08

### Added
- **Count the Animals!** — a counting game: the toddler counts a group of big
  animal emojis and taps the answer card (large digit + dot pattern, up to 2
  rows of 5 dots) that matches. Wrong taps shake the card and let the child
  try again; 5 rounds per game and fewer wrong taps means more stars. Easy
  (count to 3), Medium (to 5), Big (to 10).

### Notes
- `flutter analyze`: 0 issues; 16/16 tests (new: count-game flow with a
  seeded RNG — wrong tap doesn't advance, correct tap does, star
  thresholds, double-tap guard, Big-mode boundary).

---

## [1.4.4] — 2026-08-08

### Added
- **App launcher icon** — the app finally has a real icon: sky→pink gradient
  with a cheerful white smiling face and gold sparkles, as a modern Android
  adaptive icon (plus legacy PNGs for older launchers).
- **`tool/generate_icon.dart`** — a pure-Dart, dependency-free generator that
  rasterizes the icon analytically (no Flutter engine, no fonts) and writes
  all mipmap sizes + adaptive icon resources. Re-run it anytime the design
  changes: `dart run tool/generate_icon.dart`.

### Notes
- `flutter analyze`: 0 issues; 13/13 tests.
- New icon verified in APK (adaptive icon resolves as the launcher icon) and
  installed on device.

---

## [1.4.3] — 2026-08-08

### Added
- **Quota-reset notice** — when Pollie is out of words for the day, the
  message now includes when he'll be back, computed from Gemini's daily
  reset (midnight Pacific, DST-aware): "He'll be back at 14:00 (in about
  3 h 20 m) 😴".

### Notes
- `flutter analyze`: 0 issues; 13/13 tests (new: reset-label format test).

---

## [1.4.2] — 2026-08-08

### Fixed
- **Pollie stuck sleeping — honest reason now**: the free-tier Gemini daily
  quota can run out (it resets at midnight Pacific). Pollie now says he's
  "all out of words for today" instead of the misleading "can't reach the
  internet".
- **Fewer API requests** — a successful wake-up is cached for 5 minutes, so
  opening the companion repeatedly no longer burns a request every time
  (free-tier quota is precious).

### Notes
- `flutter analyze`: 0 issues; 12/12 tests.

---

## [1.4.1] — 2026-08-08

### Fixed
- **Mic button could seem unresponsive** — tapping the mic while Pollie was
  sleeping/thinking/speaking did nothing. Now: tapping the mic while he
  sleeps **wakes him up**, and the mic **dims** whenever it can't listen so
  it never looks broken. A speech-engine "busy" hiccup right after a
  listening session now gets one quiet retry before giving up.
- **Mic pulse rebuild storm** — sound-level updates are throttled, so the
  screen no longer rebuilds dozens of times per second while listening.

### Notes
- `flutter analyze`: 0 issues; 12/12 tests (new: mic-always-responds test).

---

## [1.4.0] — 2026-08-08

### Removed
- **Background music removed entirely** — the lullaby player, asset, and
  generator are gone. The app is silent again except for game effects.

### Added
- **Bubble Pop pop sound** — tapping a bubble now plays a playful
  synthesized "pop" (`assets/sfx/pop.wav`, regenerated with
  `tool/generate_sfx.dart`); rapid taps re-pop cleanly.

### Notes
- `flutter analyze`: 0 issues; 11/11 tests.

---

## [1.3.4] — 2026-08-08

### Improved
- **Background music re-arranged** — the lullaby is now a full music-box
  arrangement instead of a plain melody: chime-like tones (fast attack,
  long decay), a harmony line a third below the melody, a deep soft C drone,
  and a gentle two-tap echo. The piece develops: bell intro → solo melody →
  melody + harmony duet → quiet outro. Still synthesized in-repo
  (`tool/generate_music.dart`), fully original, ~56 s loop.

### Notes
- `flutter analyze`: 0 issues; 11/11 tests.

---

## [1.3.3] — 2026-08-08

### Improved
- **Global error handling** — uncaught errors are logged instead of crashing;
  the scary red debug screen is replaced with a friendly fallback
  ("Oops! … keep playing! 🐻") so a build error can never frighten a toddler.
- **Pollie cleans up properly** — leaving the companion (or backgrounding the
  app) now stops the microphone and the TTS engine immediately; no stale
  "listening" state after resume.
- **Speech-engine hiccups are caught** — a failed `listen()` falls back to
  the idle smile instead of an unhandled error.
- **Long chats stay healthy** — only the last 20 conversation turns are sent
  to Gemini, so marathon toddler sessions can't blow the context window.

### Notes
- `flutter analyze`: 0 issues; 11/11 tests.

---

## [1.3.2] — 2026-08-08

### Improved
- **Confetti is now cheap** — each emoji's text is laid out once and reused
  every frame (previously 70 text layouts ran per frame at 60fps, which
  janked win celebrations and drained battery while the overlay was open).
- **Jigsaw drags repaint less** — each piece is isolated in a
  `RepaintBoundary`, so dragging repaints only the piece under the finger
  instead of all 9 pieces.
- **Smoother chat auto-scroll** — streaming replies now jump instead of
  restarting a scroll animation on every chunk (no more jitter).

### Notes
- `flutter analyze`: 0 issues; 11/11 tests.

---

## [1.3.1] — 2026-08-08

### Added
- **Kid-safety layers for Pollie** (defense in depth):
  - **Strictest Gemini safety filters** — every harm category (sexual,
    harassment, hate speech, dangerous content) is blocked at the lowest
    threshold (`BLOCK_LOW_AND_ABOVE`) for both input and output.
  - **Hardened system prompt** — Pollie is forbidden from sex, dating,
    violence, drugs, bad words; inappropriate talk gets a gentle redirect.
  - **Local content guard** (`lib/services/kid_safety.dart`) — adult/abusive
    words (English + Indonesian) are caught before they reach Google (input)
    and before they reach the child (output); the child only ever sees a
    gentle "that's not a nice thing to say" message.

### Notes
- `flutter analyze`: 0 issues; 11/11 tests (new: blocked-input widget test +
  KidSafety unit test).

---

## [1.3.0] — 2026-08-08

### Added
- **Background music** — a soft music-box lullaby (synthesized in-repo,
  `tool/generate_music.dart`) loops on the home + game screens and pauses
  while the app is in the background. It stops automatically while the
  Pollie companion is open, and resumes when you leave it.

### Changed
- **Pollie speaks like a person** — the system prompt now asks for relaxed,
  natural, casual replies (no robot-speak, no forced emojis, no *roleplay*
  markers), and the spoken voice is picked from the device's best-quality
  (preferably female) TTS voice with a gentle pitch + warm pace — closer to
  a kid/Ms-Rachel feel.
- **TTS reads plain text only** — emojis and asterisks are stripped before
  speaking, so Pollie never reads "smiling face with heart eyes" aloud.
- **Home footer centered** — "Made with ❤️ for our toddler" is now properly
  centered.

### Notes
- `flutter analyze`: 0 issues; tests passing.
- New package: `audioplayers`. New asset: `assets/music/lullaby.wav`.

---

## [1.2.0] — 2026-08-08

### Added
- **Voice conversation with Pollie** — a big 🎤 button lets the child talk:
  speech is transcribed (Google speech-to-text, device language), answered by
  Gemini, and spoken aloud. After each reply Pollie **listens again
  automatically**, so a toddler can chat hands-free like in the Gemini app.
  - Live transcript bar shows what Pollie hears while listening.
  - The mic pulses with the sound level; Pollie's face shows his mood:
    😴 sleeping · 😊 awake · 👂 listening · 🤔 thinking · 🗣️ speaking.
  - New permission: `RECORD_AUDIO` (prompted once on first use).
  - New package: `speech_to_text`.

### Notes
- `flutter analyze`: 0 issues; tests passing.
- Voice flow verified on-device (permission grant → listening state →
  graceful timeout); actual speech recognition uses the device's Google
  speech service.

---

## [1.1.1] — 2026-08-08

### Changed
- **Buddy renamed to Pollie 🦜** (a cheerful little parrot) — name, avatar,
  home button, and the Gemini system prompt now all say Pollie.
- **Pollie now has a mood/status face** in the chat header: sleeping 😴 while
  offline (or before the first connection), smiling 😊 once Gemini answers a
  connectivity probe. Tapping the face retries waking up.
- On wake, Pollie greets the child with a spoken and written
  "Hi kids! Let's talk with me 🦜".

### Notes
- `flutter analyze`: 0 issues; tests passing.
- Live Gemini build verified on-device (greeting + smiling status + a real
  chat reply).

### Fixed
- **Pollie couldn't wake up / reply** — two API-generation issues:
  - The tiny `maxOutputTokens` cap left nothing for the current (thinking)
    flash models, which returned empty content (SDK threw "Unhandled format
    for Content"). Budget raised generously.
  - The SDK 0.4.7 sends `Content.system` as `systemInstruction` with a
    `role: 'system'` field, which the current Gemini API rejects. Pollie's
    rules now ride along as the first user turn instead.
- Model set to `gemini-flash-latest` (the self-updating alias; named flash
  models like 2.0/2.5 are no longer available to new free-tier keys).

---

## [1.1.0] — 2026-08-08

### Added
- **Buddy 🐻 — a talking companion** on the home screen (bottom-right
  button). Tap it to chat: replies stream in as speech bubbles and are
  spoken aloud with the system text-to-speech engine. Toddler-friendly tap
  chips ("Tell me a story! 🐰", "What does a cow say? 🐮"…) plus a text
  field for grown-ups. Powered by Google Gemini (default model
  `gemini-2.5-flash`), with a toddler-safe system prompt (very short
  answers, same language as the child, no dangerous suggestions).
  - **API key**: passed at build time via
    `--dart-define=GEMINI_API_KEY=...` — never stored in the repo. Without
    a key the companion shows a friendly "ask a grown-up" message.
  - New packages: `google_generative_ai`, `flutter_tts`.

### Changed
- **INTERNET permission added** — required for Buddy. All games still work
  fully offline.
- New `lib/services/buddy_service.dart`; home screen now has a
  floating action button.

### Notes
- `flutter analyze`: 0 issues; tests passing (companion fallback + Buddy
  button checks added).
- Companion verified on-device; live Gemini replies require the API key.

---

## [1.0.5] — 2026-08-08

### Fixed
- **Laggy placement + vanishing icons, for real this time** — the previous
  fixes scaled the picture emoji with FittedBox/Transform. Impeller
  re-rasterizes text glyphs based on their transform scale, so every
  animation frame re-rasterized a ~300px emoji (the lag) and the glyph atlas
  eventually failed, stopping ALL emoji rendering app-wide (the vanishing
  icons). The picture is now rendered at its natural font size with zero
  transforms, and the placement pop animation (an animated transform on a
  text-bearing piece) was removed entirely.

### Changed
- Piece placement is now instant (haptic + snap, no scale animation).

### Notes
- `flutter analyze`: 0 issues; 7/7 tests passing.
- Verified on-device by playing a full 2×2 jigsaw round via adb (input
  swipes + screenshots) — pieces snap cleanly and every icon stays visible
  after placement and after the win overlay.

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
