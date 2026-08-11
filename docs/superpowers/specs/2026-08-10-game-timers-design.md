# Game timers and the lose state

Branch: `feat/game-timers` → v1.11.0

## Goal

Every game gets a countdown a child can read without numbers. Easy 30 s,
Medium 60 s, Big 120 s, one clock for the whole game. Running out is a real
loss: a lose overlay, `lose.mp3`, and Try again / Home.

Depends on `feat/audio` for `SoundEffects.lose()`.

## Durations

```dart
enum GameLevel { easy, medium, big }
// easy 30s, medium 60s, big 120s
```

Every game screen takes a `GameLevel level` constructor argument, passed from
`home_screen.dart` alongside the existing difficulty parameters. Levels are
already expressed there as three `LevelOption`s per game, so this is one extra
argument per call site.

Bubble Pop has no level picker today — it runs endless rounds of 8 pops. It
gains a `LevelsScreen` like the others: Easy 6 pops, Medium 8, Big 12, and the
round-escalation speed-up is kept within the single timed game.

## Round counts

Count the Animals and Find It are both 5 rounds regardless of level
(`_roundsToWin = 5` in each). One 30 s clock across 5 rounds is 6 s per
question, which a four-year-old will not make. Easy drops to **3 rounds** in
both games; Medium and Big stay at 5.

`_roundsToWin` becomes an instance getter derived from `level` rather than a
`static const`. The progress-dot row that renders `for (var i = 0; i <
_roundsToWin; i++)` picks the change up for free.

## Components

### `lib/widgets/game_timer.dart` (new)

Two things in one file, because they are useless apart:

**`GameTimerController extends ChangeNotifier`** — owns the clock.

```dart
GameTimerController({required Duration total});
void start();          // idempotent; the first call wins
void pause();          // app backgrounded, or the game is over
void resume();
void reset();
Duration get remaining;
double get fraction;   // 1.0 → 0.0
bool get expired;
```

Driven by a single `Timer.periodic(Duration(milliseconds: 100))` — fine
granularity for a smooth bar, coarse enough to be cheap. Ticks stop on expiry
and fire one final notification.

**`GameTimerBar extends StatelessWidget`** — the visual, listening to the
controller.

- A full-width rounded bar that shrinks left to right.
- Green above 50 %, amber 20–50 %, red below 20 %. Colour is the primary
  signal, since the target user cannot read a clock.
- Under 10 s remaining the bar pulses (scale 1.0 ↔ 1.06) and an ⏰ appears
  beside it.
- No digits. A number would be noise to a toddler and the parent can see the
  bar.

### Starting the clock

The clock starts on **first interaction**, not on screen entry — a child
looking at a fresh board should not be losing time before touching anything.
Concretely, `controller.start()` is called from:

- `PairDragGame` (jigsaw, animal food): the first `onPanStart`.
- Memory, Find It, Count: the first card/answer tap.
- Bubble Pop: the first pop.
- Which Animal? (branch 4): the first time the sound is played.

`start()` is idempotent so every one of those can call it unconditionally.

### Pausing

- `didChangeAppLifecycleState` → `paused`/`hidden` pauses; `resumed` resumes.
  Each game screen already has, or gains, a `WidgetsBindingObserver`.
  `CompanionScreen` shows the pattern to copy.
- Winning pauses the clock before the celebration appears, so the overlay is
  not racing a timeout.
- The reset button (🔁) resets the clock along with the board.

### `lib/widgets/game_over_overlay.dart` (new)

A sibling of `CelebrationOverlay` rather than a flag on it. The two share only
a dimmed backdrop; the celebration's confetti, stars and win sound are all
wrong here, and threading `isLoss` through would make an already-branchy widget
worse.

- ⏰ at 80 px, "Time's up!" — same type scale as the celebration.
- No stars, no confetti.
- Buttons: "Try again 🔁" (primary, resets the game) and "Home 🏠"
  (secondary, pops).
- Fires `SoundEffects.instance.lose()` once in `initState`, matching how
  `CelebrationOverlay` fires the win sound after `feat/audio`.

### Per-game wiring

Each of the seven game screens:

1. Takes `GameLevel level`.
2. Holds a `GameTimerController` created in `initState` from
   `level.duration`, disposed in `dispose`.
3. Renders `GameTimerBar` in the header row, under the existing home/title/
   reset row.
4. Listens for expiry → `setState(() => _lost = true)`, and guards all input
   on `!_lost` the way `bubble_pop_screen.dart:105` already guards on `_won`.
5. Shows `GameOverOverlay` when `_lost`.

Bubble Pop's `_roundComplete` guard and its pending celebration timer
(`bubble_pop_screen.dart:46-60`) need the same treatment as `_won`: a timeout
landing during that 400 ms pop-animation window must not show both overlays.
Rule: whichever of `_won`/`_lost` is set first wins, and the timer is paused
the moment either is set.

## Testing

- `GameTimerController`: start is idempotent; pause/resume preserves remaining
  time; expiry notifies exactly once; reset restores the full duration.
- `GameLevel.duration` returns 30/60/120 s.
- `_roundsToWin` is 3 on Easy and 5 otherwise for Count and Find It.
- Widget test: a game screen with an expired controller shows
  `GameOverOverlay` and not `CelebrationOverlay`.
- Widget test: winning on the final tick shows the celebration, not the loss.

## Risks

- **Difficulty.** 30 s is a real constraint for a toddler even on Easy. The
  durations are fixed by explicit decision; if play-testing says they are too
  harsh, the one place to change them is `GameLevel.duration`.
- Seven screens change at once. Each is a small, identical diff, and the shared
  widgets carry the logic — but this is the branch most likely to need a
  careful review pass.

## Out of scope

- Difficulty-tuned durations per game.
- Persisting best times or scores.
- Pausing by choice (a pause button).
