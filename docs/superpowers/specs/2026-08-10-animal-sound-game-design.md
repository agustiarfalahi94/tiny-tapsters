# Which Animal? — guess the animal by its sound

Branch: `feat/animal-sounds-game` → v1.12.0

Depends on `feat/audio` (win/lose sounds) and `feat/game-timers` (`GameLevel`,
countdown, loss overlay).

> **Superseded on assets and licensing (v1.17.0).** Two decisions below did not
> hold:
>
> - **"Keys must be members of `kAnimalEmojis`"** (§Assets, §Testing) was
>   reversed. A listening game needs no food pairing, so requiring one meant a
>   tiger could have no roar until someone invented its dinner. 🐷 🐦 🐯 now
>   exist only in this game (`animal_sounds.dart`), and the test checks for
>   duplicates and consistent emoji instead.
> - **"CC0 / public-domain only"** and **"a credits screen is out of scope"**
>   were both dropped. The game ships fifteen calls, fourteen under the Pixabay
>   Content License and 🐶 under CC0, and `CreditsScreen` exists — see
>   `ASSET_CREDITS.md` and `lib/data/asset_credits.dart`. The one rule that did
>   hold is **never ShareAlike**, now enforced by
>   `animal_sound_test.dart:75`.
>
> The game itself (rounds, choices, the unlimited replay, the third player,
> ducking) shipped as written.

## Goal

A seventh game: a big speaker button plays an animal call, two to five emoji
cards sit below it, tap the animal that made the sound. Easy 2 choices, Medium
3, Big 5.

This is the first game in the app that a blind-drawn emoji cannot carry — it
needs real audio assets, and that is the bulk of the work.

## Assets

### Sourcing

CC0 / public-domain only, by decision. Primary sources:

- **Wikimedia Commons**, especially
  `Category:Audio files of animal sounds from the United States Fish and
  Wildlife Service` — US government work, public domain.
- **Pixabay** audio under the Pixabay Content License (free for commercial use,
  no attribution required).

Every candidate file's licence is verified on its source page before download.
Anything that turns out to be CC-BY, CC-BY-SA or "free for non-commercial" is
rejected — a credits screen is out of scope for this branch.

### Per-animal coverage

Candidates from `kAnimalEmojis` (`animal_food_screen.dart:16`), which stays the
single source of truth for the animal pool:

| Likely to find | Unlikely / no iconic sound |
|---|---|
| 🐮 cow, 🐴 horse, 🐶 dog, 🐱 cat, 🐵 monkey, 🐻 bear, 🐔 chicken, 🦁 lion, 🐘 elephant, 🐸 frog, 🐧 penguin, 🐭 mouse | 🐰 rabbit, 🦒 giraffe, 🦋 butterfly |

**Coverage is not guaranteed and must not be faked.** An animal without a
verified CC0 recording is simply absent from this game and unchanged in every
other game. The game needs a minimum of **6** animals to be worth shipping
(Big needs 5 choices plus variety across 5 rounds); if fewer than 6 are found,
stop and report rather than substituting a poor-quality or wrongly-licensed
file.

### Processing

Each file: trimmed to the clearest ≤ 2 s of call, normalised, transcoded to
mono AAC 64 kbps via `afconvert` (same tool as `feat/audio` — no ffmpeg on this
machine), landing in `assets/animal_sounds/<name>.m4a` at roughly 20–40 KB
each. Twelve animals is under 500 KB total.

### `ASSET_CREDITS.md` (new, repo root)

One row per file: bundled filename, source URL, original title, author,
licence, and the date verified. CC0 obliges nothing, but provenance is what
makes the licence claim checkable a year from now — the file exists for us, not
for the licence.

### `lib/data/animal_sounds.dart` (new)

```dart
const kAnimalSounds = <String, String>{
  '🐮': 'assets/animal_sounds/cow.m4a',
  ...
};
```

Keys must be members of `kAnimalEmojis`; a test asserts this so a typo cannot
silently create an animal that exists only in this game.

## The game

`lib/screens/animal_sound_screen.dart`, following the structure of
`find_it_screen.dart` (the closest existing game: rounds, a prompt, a grid of
emoji answer cards, wrong-tap-based stars).

- `AnimalSoundScreen({required int choices, required GameLevel level})` —
  choices 2 / 3 / 5.
- 5 rounds; Easy 3 rounds, per the timers spec.
- Each round: pick a target from `kAnimalSounds.keys`, plus `choices - 1`
  distractors, shuffle, lay out as cards.
- A large 🔊 button at the top plays the target's call. It plays automatically
  once when the round starts, and replays on tap — **unlimited**, because this
  is a listening game and re-listening is the skill being practised, not
  cheating.
- Correct tap: the card flips to show a ✅ tint, `SoundEffects.pop()`, next
  round after a short beat.
- Wrong tap: a shake on that card, `_wrong++`, the round continues. Same
  forgiving model as Find It — nothing is ever taken away.
- Stars: 3 for no wrong taps, 2 for ≤ 2, else 1. Matches
  `find_it_screen.dart:111`.
- The countdown starts on the first sound playback (see the timers spec).

### Playback

Animal calls go through a **third** player, separate from music and from
`SoundEffects`. `SoundEffects.pop()` stops its player before each play so
rapid taps re-trigger — that would cut an animal call short. Add
`SoundEffects.animal(String assetPath)` backed by its own `AudioPlayer`, or a
small `AnimalSoundPlayer`; either way it must not share with `pop()`.

Background music ducks to 0.25 while a call plays and restores after, reusing
`MusicService.duck()`/`unduck()` from `feat/audio`. A child cannot identify a
cow over a backing track.

### Home screen entry

A `_GameCard` with 🔊 "Which Animal?" / "Listen and find the animal!", opening
a `LevelsScreen` with Easy 🐣 2 choices, Medium 🐥 3 choices, Big 🐤 5 choices,
using the same three colours as every other game.

## Testing

- Every key of `kAnimalSounds` is in `kAnimalEmojis`.
- Every value in `kAnimalSounds` is listed in `pubspec.yaml`'s assets.
- Round generation: exactly `choices` cards, the target is among them, no
  duplicate animals in one round.
- Star thresholds at 0, 2 and 3 wrong taps.
- Widget test: the screen renders `choices` cards and a play button.

## Risks

- **Asset availability is the whole risk.** If sourcing yields fewer than 6
  verified CC0 animals, this branch stops and the user chooses: provide the
  sounds, or allow CC-BY plus a credits screen. Report rather than improvise.
- Emoji-to-sound mapping has to be obvious to a toddler. A generic "bird chirp"
  for 🐧 penguin is not — penguins bray. Any recording that does not
  unmistakably read as its emoji gets dropped, even if the licence is fine.

## Out of scope

- Recording our own sounds.
- A credits screen (not needed for CC0).
- Naming the animal in text after a correct answer, the way Animal Food names
  the food. Worth considering later.
