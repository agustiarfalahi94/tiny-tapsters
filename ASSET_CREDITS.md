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

From Wikimedia Commons. CC0, public domain and CC BY — never ShareAlike,
which would reach into the app itself. The CC BY entries are credited in-app
on the Credits screen, reachable from the home screen. Each is trimmed to its loudest ~2 seconds,
normalised to −16 dBFS RMS and encoded as mono AAC at 96 kbps / 44.1 kHz by
`tool/normalize_audio.py`. Re-fetch the sources from the links below to rebuild
them.

| Bundled as | Source | Author | Licence |
|---|---|---|---|
| 🐱 `cat.m4a` | [Weibliche Britisch Kurzhaar will Futter C1277 MIAUEN.wav](https://commons.wikimedia.org/wiki/File:Weibliche_Britisch_Kurzhaar_will_Futter_C1277_MIAUEN.wav) | PantheraLeo1359531 | CC BY 4.0 |
| 🐶 `dog.m4a` | [Ladrido perro.ogg](https://commons.wikimedia.org/wiki/File:Ladrido_perro.ogg) | Wikimedia Commons contributor | CC0 |
| 🐴 `horse.m4a` | [Wiehern.ogg](https://commons.wikimedia.org/wiki/File:Wiehern.ogg) | Wikimedia Commons contributor | Public domain |
| 🐔 `chicken.m4a` | [Coq qui chante (DenisChardonnet).wav](https://commons.wikimedia.org/wiki/File:Coq_qui_chante_(DenisChardonnet).wav) | Wikimedia Commons contributor | CC0 |
| 🦁 `lion.m4a` | [Lionroar.wav](https://commons.wikimedia.org/wiki/File:Lionroar.wav) | Jonathan Growcott, Alex Lobora, Andrew Markham, Charlotte E. | CC BY 4.0 |
| 🐵 `monkey.m4a` | [Vervet Monkey (Chlorocebus pygerythrus) (W CERCOPITHECUS AETHIOPS R2 C2).ogg](https://commons.wikimedia.org/wiki/File:Vervet_Monkey_(Chlorocebus_pygerythrus)_(W_CERCOPITHECUS_AETHIOPS_R2_C2).ogg) | Wikimedia Commons contributor | CC BY 4.0 |
| 🐘 `elephant.m4a` | [Elephant voice - trumpeting.ogg](https://commons.wikimedia.org/wiki/File:Elephant_voice_-_trumpeting.ogg) | Wikimedia Commons contributor | CC0 |
| 🐸 `frog.m4a` | [CouchsSpadefootToad SaguaroNP 20110705.ogg](https://commons.wikimedia.org/wiki/File:CouchsSpadefootToad_SaguaroNP_20110705.ogg) | Wikimedia Commons contributor | Public domain |

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
