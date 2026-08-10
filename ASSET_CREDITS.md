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
| 🐶 `dog.m4a` | [Ladrido perro.ogg](https://commons.wikimedia.org/wiki/File:Ladrido_perro.ogg) | CC0 |
| 🐴 `horse.m4a` | [Wiehern.ogg](https://commons.wikimedia.org/wiki/File:Wiehern.ogg) | Public domain |
| 🐔 `chicken.m4a` | [Coq qui chante (DenisChardonnet).wav](https://commons.wikimedia.org/wiki/File:Coq_qui_chante_(DenisChardonnet).wav) | CC0 |
| 🦁 `lion.m4a` | [Lion raring-sound1TamilNadu178.ogg](https://commons.wikimedia.org/wiki/File:Lion_raring-sound1TamilNadu178.ogg) | Public domain |
| 🐘 `elephant.m4a` | [Elephant voice - trumpeting.ogg](https://commons.wikimedia.org/wiki/File:Elephant_voice_-_trumpeting.ogg) | CC0 |
| 🐸 `frog.m4a` | [CouchsSpadefootToad SaguaroNP 20110705.ogg](https://commons.wikimedia.org/wiki/File:CouchsSpadefootToad_SaguaroNP_20110705.ogg) | Public domain |

### Animals with no free recording

🐮 the cow, 🐵 monkey, 🐧 penguin, 🐭 mouse, 🐻 bear and 🦒 giraffe have no CC0
or public-domain recording that could be verified, so they do not appear in
"Which Animal?". They are unchanged in every other game.

The cow is the one that hurts. Commons has nothing usable: the searches return
*Lingua Libre* files of people pronouncing the word "cow" in various languages,
and one recording of a fart. Adding it means accepting CC-BY material and
shipping a credits screen in the app.

The 🐴 horse and 🐘 elephant recordings are the best free ones that exist, but
both sources are around 60–100 kbps and they stay noticeably quieter than the
rest, because lifting them to match would amplify their noise floor into
crackle. CC-BY would fix these too.
