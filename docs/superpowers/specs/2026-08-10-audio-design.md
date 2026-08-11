# Audio: background music and finish sounds

Branch: `feat/audio` → v1.9.0

## Goal

Two looping background tracks (main theme on the menus, game song in the games)
and three finish sounds (lose, 1–2 stars, 3 stars), with a mute button a parent
can reach in one tap.

## Background

Background music existed once before and was removed because it sounded bad —
it was synthesised in `tool/generate_sfx.dart`, not composed. These are real
Suno tracks, so that objection no longer applies. `MEMORY.md`'s
`no-background-music` note must be updated when this branch merges, or a future
agent will "helpfully" remove the music again.

## Assets

Sources (user-provided, in `~/Downloads`):

| Source file | Bundled as | Transcode |
|---|---|---|
| `Tiny Tappers - Main Theme.mp3` (3:10, 4.6 MB, 192 kbps stereo) | `assets/music/main_theme.m4a` | mono AAC 96 kbps (~2.2 MB) |
| `Tiny Tappers - Game Song.mp3` (0:30, 760 KB) | `assets/music/game_song.m4a` | mono AAC 96 kbps (366 KB, verified) |
| `lose.mp3` (3.03 s) | `assets/sfx/lose.m4a` | mono AAC 64 kbps |
| `2 stars.mp3` (3.03 s) | `assets/sfx/win_low.m4a` | mono AAC 64 kbps |
| `3 stars.mp3` (3.03 s) | `assets/sfx/win_high.m4a` | mono AAC 64 kbps |

Transcode command (macOS, no ffmpeg needed — `afconvert` is verified working):

```bash
afconvert -f m4af -d aac -b 96000 --mix -c 1 in.mp3 out.m4a
```

The app is emoji-only and has no image assets; adding 5.3 MB of stereo music to
a toddler app that currently ships almost no assets is not worth it. Mono at
96 kbps through a phone speaker is indistinguishable in practice.

All five files get added to `pubspec.yaml`'s `assets:` list.

**Known limitation:** AAC carries encoder delay/padding, so a loop seam is
audible as a short gap. Acceptable for background music under gameplay. If it
bothers us later, the fix is a second player crossfading at a known loop point,
not a different codec — `afconvert` cannot write gapless Ogg Vorbis.

## Components

### `lib/services/music_service.dart` (new)

A singleton mirroring `SoundEffects`, with its own `AudioPlayer`. Music must
never share a player with SFX: `SoundEffects.pop()` calls `stop()` before every
play so rapid taps re-trigger cleanly, which would kill the music.

```dart
enum MusicTrack { menu, game }

class MusicService {
  static final MusicService instance = MusicService._();

  bool get enabled;
  Future<void> setEnabled(bool value);   // stops or resumes immediately
  Future<void> play(MusicTrack? track);  // null = silence (Pollie's screen)
  Future<void> duck();                   // volume → 0.25, for finish sounds
  Future<void> unduck();                 // volume → 1.0
}
```

- `ReleaseMode.loop` on the player, so a track repeats without our involvement.
- `play` is a no-op when the requested track is already the current one — a
  `didPop` back to the menu must not restart the theme from the top.
- Every method is wrapped in try/catch and logs via `debugPrint`, matching
  `SoundEffects`. Audio failing must never crash a game.
- Base volume 0.45. Music sits under gameplay; the pop SFX has to cut through.

### `lib/services/music_route_observer.dart` (new)

`NavigatorObserver` subclass wired into `MaterialApp.navigatorObservers` in
`main.dart`. It maps the route now on top of the stack to a track:

- `HomeScreen`, `LevelsScreen` → `MusicTrack.menu`
- `CompanionScreen` → `null` (silence; music would fight Pollie's TTS and the
  microphone would hear it)
- anything else (all game screens) → `MusicTrack.game`

Implemented on `didPush`, `didPop`, `didReplace` and `didRemove` by reading
`route.settings` / the built widget type.

**Why an observer instead of per-screen `initState`:** popping a game route
does not re-run `HomeScreen.initState`, so per-screen calls would leave the
game song playing over the menu. Centralising it also means the new sound game
in branch 4 gets correct music for free.

To let the observer see widget types, `_open()` in `home_screen.dart` and the
level screens keep using `MaterialPageRoute`, and the observer inspects
`route is MaterialPageRoute` → `route.builder` result type. Simpler and more
robust: give every pushed route a `RouteSettings(name: ...)` and switch on the
name. **Decision: use named `RouteSettings`** — inspecting a builder's return
type means building the widget twice.

### `lib/services/sound_effects.dart` (extend)

```dart
Future<void> win(int stars);  // stars >= 3 → win_high, else win_low
Future<void> lose();
```

Both duck the music, play, and unduck when the clip finishes (3.03 s, so a
timer is unnecessary — use the player's `onPlayerComplete` stream). These use a
**separate** player from `pop()`: a win sound must not be cut off by a stray
pop, and `pop()`'s `stop()`-first behaviour would do exactly that.

### `lib/widgets/celebration_overlay.dart` (extend)

The overlay currently takes `stars` but plays nothing. Add an
`onShown`-equivalent: convert to a `StatefulWidget` and fire
`SoundEffects.instance.win(stars ?? 3)` once in `initState`. Games that pass no
star rating (Jigsaw, Animal Food, Bubble Pop) finish successfully, so they get
the 3-star sound. *(Superseded: all seven games rate stars now — Jigsaw and
Animal Food from wrong drops, Bubble Pop from wrong catches — so the
`?? 3` fallback is no longer reached from a game screen.)*

This keeps every game's win sound correct without touching six screens.

### Mute button

A `RoundButton` with 🔊 / 🔇 in the home screen header row, beside the title.
`HomeScreen` becomes a `StatefulWidget` to hold the toggle state.

Session-only by explicit decision — no `shared_preferences`, no new dependency,
and the app keeps its zero-storage property.

## Testing

- `MusicService.play` is idempotent for the same track (no restart).
- `MusicService.setEnabled(false)` stops playback; `true` resumes the current
  track.
- The route observer maps home/levels → menu, companion → null, a game → game.
- `SoundEffects.win(3)` and `win(2)` select different assets.
- `CelebrationOverlay` triggers exactly one win sound per appearance.

Player interaction is behind the service singletons, so tests target the
mapping and state logic rather than real audio. Existing 24 tests must stay
green.

## Out of scope

- Persisting the mute choice across launches.
- Per-game music.
- Volume slider.
