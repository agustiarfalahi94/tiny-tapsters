# Asset credits

Everything bundled with Tiny Tapsters, where it came from, and under what
licence. CC0 and public-domain works oblige nothing — this file exists so the
claim stays checkable a year from now, not because anyone requires it.

Verified 2026-08-10.

## Music and sound effects

`assets/music/main_theme.m4a`, `assets/music/game_song.m4a`,
`assets/sfx/win_high.m4a`, `assets/sfx/win_low.m4a`, `assets/sfx/lose.m4a` —
commissioned for this app by the author (generated with Suno). Normalised and
re-encoded to mono AAC by `tool/normalize_audio.py`.

`assets/sfx/pop.wav` — synthesised by `tool/generate_sfx.dart` in this repo.

## Animal calls

Almost all from Pixabay, whose Content License permits use in apps, commercial
or not, with no attribution required — they are credited anyway so provenance
stays checkable. The dog is CC0 from Wikimedia Commons.

Each is trimmed to its loudest ~2 seconds, normalised to −16 dBFS RMS and
encoded as mono AAC at 96 kbps / 44.1 kHz by `tool/normalize_audio.py`.

| Bundled as | Source | Author | Licence |
|---|---|---|---|
| 🐱 `cat.m4a` | [cat sound effect](https://pixabay.com/sound-effects/) | Pixabay contributor | Pixabay Content License |
| 🐶 `dog.m4a` | [Ladrido perro.ogg](https://commons.wikimedia.org/wiki/File:Ladrido_perro.ogg) | Wikimedia Commons contributor | CC0 |
| 🐮 `cow.m4a` | [cow sound effect](https://pixabay.com/sound-effects/) | Pixabay contributor | Pixabay Content License |
| 🐴 `horse.m4a` | [horse sound effect](https://pixabay.com/sound-effects/) | Pixabay contributor | Pixabay Content License |
| 🐷 `pig.m4a` | [pig sound effect](https://pixabay.com/sound-effects/) | Pixabay contributor | Pixabay Content License |
| 🐔 `chicken.m4a` | [chicken sound effect](https://pixabay.com/sound-effects/) | Pixabay contributor | Pixabay Content License |
| 🐦 `bird.m4a` | [bird sound effect](https://pixabay.com/sound-effects/) | Pixabay contributor | Pixabay Content License |
| 🐭 `mouse.m4a` | [mouse sound effect](https://pixabay.com/sound-effects/) | Pixabay contributor | Pixabay Content License |
| 🐸 `frog.m4a` | [frog sound effect](https://pixabay.com/sound-effects/) | Pixabay contributor | Pixabay Content License |
| 🦁 `lion.m4a` | [lion sound effect](https://pixabay.com/sound-effects/) | Pixabay contributor | Pixabay Content License |
| 🐯 `tiger.m4a` | [tiger sound effect](https://pixabay.com/sound-effects/) | Pixabay contributor | Pixabay Content License |
| 🐵 `monkey.m4a` | [monkey sound effect](https://pixabay.com/sound-effects/) | Pixabay contributor | Pixabay Content License |
| 🐻 `bear.m4a` | [bear sound effect](https://pixabay.com/sound-effects/) | Pixabay contributor | Pixabay Content License |
| 🐘 `elephant.m4a` | [elephant sound effect](https://pixabay.com/sound-effects/) | Pixabay contributor | Pixabay Content License |
| 🐧 `penguin.m4a` | [penguin sound effect](https://pixabay.com/sound-effects/) | Pixabay contributor | Pixabay Content License |

### Notes

🦒 the giraffe and 🐰 the rabbit have no call in the game — neither makes a
sound a child would recognise.

🐘 the elephant's source is 11 kHz, noticeably lower fidelity than the rest.
It was chosen for being the *right* sound rather than the best-recorded one.
