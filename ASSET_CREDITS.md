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

From Wikimedia Commons, CC0 or public domain only. Each is trimmed to its loudest ~2 seconds,
normalised to −16 dBFS RMS and encoded as mono AAC at 96 kbps / 44.1 kHz by
`tool/normalize_audio.py`. Re-fetch the sources from the links below to rebuild
them.

| Bundled as | Source | Licence |
|---|---|---|
| 🐱 `cat.m4a` | [Meow of a Siamese cat - freemaster2.wav](https://commons.wikimedia.org/wiki/File:Meow_of_a_Siamese_cat_-_freemaster2.wav) | CC0 |
| 🐴 `horse.m4a` | [Wiehern.ogg](https://commons.wikimedia.org/wiki/File:Wiehern.ogg) | Public domain |
| 🐔 `chicken.m4a` | [Medium rooster crowing.ogg](https://commons.wikimedia.org/wiki/File:Medium_rooster_crowing.ogg) | Public domain |
| 🦁 `lion.m4a` | [Lion raring-sound1TamilNadu178.ogg](https://commons.wikimedia.org/wiki/File:Lion_raring-sound1TamilNadu178.ogg) | Public domain |
| 🐘 `elephant.m4a` | [Elephant voice - trumpeting.ogg](https://commons.wikimedia.org/wiki/File:Elephant_voice_-_trumpeting.ogg) | CC0 |
| 🐸 `frog.m4a` | [CouchsSpadefootToad SaguaroNP 20110705.ogg](https://commons.wikimedia.org/wiki/File:CouchsSpadefootToad_SaguaroNP_20110705.ogg) | Public domain |

### Animals with no free recording

🐮 cow, 🐶 dog, 🐵 monkey, 🐧 penguin, 🐭 mouse, 🐻 bear and 🦒 giraffe have no
CC0 or public-domain recording that could be verified, so they do not appear
in "Which Animal?". They are unchanged in every other game. Note that this
leaves out the cow and the dog — the two animals a toddler knows best. Closing
that gap means either finding free recordings or accepting CC-BY material and
shipping a credits screen inside the app.
