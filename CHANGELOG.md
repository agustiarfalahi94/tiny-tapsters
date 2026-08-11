# Changelog

All notable changes to Tiny Tapsters are documented here.
Format: **Added** · **Fixed** · **Changed** · **Removed** · **Improved**

---

## [1.21.3] — 2026-08-11

### Fixed
- **🦁 and 🐯 no longer share a board in "Which Animal?".** Both are big-cat
  roars, and the two recordings measure as near-identical — 1236 against 1244
  zero-crossings a second, where a bear or a dog sits far away. With both on
  screen the round could not be answered by listening, which is the entire
  game. Neither animal was removed; they simply never appear together, the same
  rule that keeps 🍃 and 🌿 off one board in Animal Food.

### Notes
- The first attempt excluded only the *answer's* twin, which still let both
  cats appear whenever the answer was a third animal. The test caught it, and
  it was confirmed to fail again with the rule taken out.
- `flutter analyze`: 0 issues; 105/105 tests.

---

## [1.21.2] — 2026-08-11

### Fixed
- **The dots on the answer cards in Count the Animals touched the edges.** They
  ran flush to the rounded border, and on Big — ten dots in two rows — the
  bottom row sat right on it. The cards now have padding inside, so the number
  and the dots sit in clear space.

### Notes
- `flutter analyze`: 0 issues; 104/104 tests.

---

## [1.21.1] — 2026-08-11

### Fixed
- **The Indonesian footer ran underneath Pollie's button.** "Dibuat dengan ❤️
  untuk anak kami" is longer than the English line, which was short enough to
  miss the bird. It now keeps clear of the corner and wraps if it needs to.

### Notes
- Verified on the device: the flag switches every card, the tagline, Pollie's
  bubble and the in-game labels; each game speaks its name (the TTS engine was
  seen starting and stopping in the log); and the choice **survived a reinstall
  and restart**, which is what the stored preference was for.
- `flutter analyze`: 0 issues; 104/104 tests.

---

## [1.21.0] — 2026-08-11

### Added
- **Bahasa Indonesia**, switchable with the flag button on the home screen.
  English stays the default. Every sentence in the app is translated — the
  games, the level pickers, the win and lose screens, the credits, and all of
  Pollie's own words.
- **Each game says its name when it opens**, in the chosen language, so a child
  who cannot read knows which game they are in. Spoken by the device rather
  than played from a recording: `flutter_tts` was already here for Pollie and
  speaks both languages, so it follows the switch for free and adds no assets.
  It respects the mute button and ducks the music underneath.

### Changed
- **Pollie replies in the chosen language**, rather than guessing from the
  child's words. Her voice, the speech recogniser and the proxy's instruction
  all follow the same setting. The old guess used a list of Indonesian stop
  words and got it wrong on short replies; that list is gone.
- **The app now remembers one thing**: the chosen language. A language that
  reset every launch would be worse than no switch, so this is the setting
  worth storing. It is one word through a small platform channel, not a
  package — nothing else is written to the device.

### Notes
- Names as specified: Find It! → **Cari Hewan Ini!**, Animal Food → **Beri
  Makan Hewan**, Which Animal? → **Tebak Suara Hewan**. The rest translated to
  match.
- Strings are getters on a class, not a map of keys, so a missing translation
  is a compile error rather than a blank label found by a child. A test also
  asserts every string differs between the two languages, which catches one
  left in English.
- `home:` in `main.dart` is deliberately **not** `const`: a const widget is
  canonicalised to one instance and Flutter skips rebuilding a subtree whose
  widget is identical, so with `const` the switch changed nothing on screen.
- Verified against the live proxy: the same question returns English or
  Indonesian according to the setting.
- `flutter analyze`: 0 issues; 104/104 tests.

---

## [1.20.0] — 2026-08-11

### Fixed
- **Icons vanished on Find It's Big board.** The wrong-answer shake rotated the
  card, and a rotation is still a transform over text — the glyph has to be
  re-rendered for every frame of it. With twelve large emoji on screen that
  empties the glyph cache and icons stop painting, the home and restart buttons
  included. The shake now slides sideways instead, which just moves pixels that
  are already drawn. Same change in Count the Animals and Which Animal?.
  Measured on the device: sixty taps across a Big board, everything still
  drawn.
- **The 1–2 star clapping was too loud.** Its *average* level is lower than the
  3-star fanfare, but clapping is all transients and its peaks reach full
  scale, which on a phone speaker reads as louder and harsher. Matching average
  levels is right for sustained sound and wrong here, so it now plays back
  about 4 dB down.

### Added
- **The screen no longer locks while the app is open.** A toddler looking at a
  jigsaw touches nothing for a minute, and the phone locking ends the game. One
  window flag in `MainActivity`, tied to the app's own window, so it lifts by
  itself when the app is backgrounded — no wake lock to leak, no permission, no
  package.

### Fixed (build)
- **A release built by CI would have shipped with Pollie switched off.** The
  workflow always passes `--dart-define=POLLIE_ENDPOINT=...`, so an unset
  repository variable passes an *empty* one — which overrode the built-in
  default rather than falling back to it. An empty value now means "not
  configured". Found while preparing to push; no released APK was affected,
  because none has been built by CI yet.

### Notes
- The silence-timer patch from 1.19.0 is confirmed working on the device:
  recogniser restarts fell from roughly one every 1–2 seconds to **two in
  twenty-five seconds** of silence. Restarts are the gaps where speech is lost,
  so this is the measurement that matters.
- `flutter analyze`: 0 issues; 97/97 tests.

---

## [1.19.0] — 2026-08-11

### Changed
- **`speech_to_text` is now vendored and patched** (`packages/`, documented in
  `packages/PATCH.md`). Android's recogniser has two silence timers: a long
  one the package exposes as `pauseFor`, and a short "probably finished" one of
  about half a second that it never sets and gives no way to set. Half a second
  is shorter than the pause between words, so the session kept ending
  mid-sentence — every one to two seconds on the test device — and each restart
  leaves a gap in which nothing is captured. That is what cut a child off, and
  later what dropped "do you" from "do you know about minecraft?".
  The patch adds two options carried through to the Android intent extras;
  the app sets the short timer to 2.5 seconds and a 3-second minimum session.

### Fixed
- The restart gap is smaller: the redundant `stop()` before restarting is now
  skipped when the session already ended on its own, and the pause between
  sessions is 60 ms instead of 120 ms. Every millisecond there is speech nobody
  captures.

### Notes
- Roughly fifteen changed lines across three upstream files, each marked
  `TINY TAPSTERS PATCH`. `analysis_options.yaml` excludes `packages/**` — it is
  upstream code, and we maintain a patch rather than its style.
- The first build after vendoring failed with "Conflicting overloads" from a
  stale Gradle cache; `flutter clean` fixed it. Worth knowing before assuming
  the patch is wrong.
- **Not verified on a device.** The phone stopped advertising over wireless
  debugging before it could be installed. Nothing about a silence timer can be
  proven by a unit test — this needs a real recogniser and a real voice.
- `flutter analyze`: 0 issues; 97/97 tests.

---

## [1.18.4] — 2026-08-11

### Fixed
- **Pollie dropped the start of what was said.** "Do you know about minecraft?"
  arrived as "know minecraft". When a recogniser session ended, whatever it was
  still guessing was thrown away — the next session's first result *assigns* to
  the partial rather than appending, so those words vanished. Sessions end
  every second or two on a real phone, so this happened constantly. The dying
  session's words are now banked before the next one starts, with the overlap
  skipped so a restatement does not stutter into "do you do you know".

### Added
- `docs/pollie-architecture-and-costs.md` — why the key lives in a Worker, the
  measured rate limits, cost per message at various scales, why Gemini rather
  than DeepSeek/Qwen/MiMo, options for charging users, and why the install id
  is not persistent. Both agent files point at it, so these questions do not
  get researched twice.

### Notes
- `flutter analyze`: 0 issues; 97/97 tests.

---

## [1.18.3] — 2026-08-10

### Fixed
- **The microphone still never closed by itself.** The give-up timer was
  re-armed on every sign of life from the recogniser — and on a real phone the
  recogniser reports activity constantly while transcribing nothing, so the
  timer was postponed forever. It is now an absolute deadline from the moment
  the mic opens: if not one word is understood in twelve seconds, the mic
  closes and sends nothing. The four-second "you have finished talking" timer
  is still re-armed, but only by *recognised words*.
- **Typed messages were silently dropped while the mic was listening.** Sending
  refuses while the app is busy, and listening counts as busy — so with the
  hands-free loop reopening the mic after every reply, four of six typed
  messages vanished in testing. Typing now closes the mic first.

### Notes
- Both found by driving the app on the device over adb, not by reading code.
  The first version of the mic fix looked correct and failed for a reason only
  a real recogniser shows: it never stops making noise.
- `flutter analyze`: 0 issues; 92/92 tests.

---

## [1.18.2] — 2026-08-10

### Fixed
- **Pollie broke permanently as soon as she used an emoji.** Dart's
  `HttpClientRequest.write` encodes with the request's charset, which defaults
  to Latin-1 when none is given. Pollie's prompt lets her use an emoji now and
  then; the moment one did, that reply entered the conversation history and
  every request afterwards threw "Contains invalid characters" for the rest of
  the session. Indonesian accented text would have done the same. The body is
  now sent as UTF-8 bytes with an explicit charset.
- **The microphone never closed on its own when nothing was understood.** The
  four-second timer was armed only by *recognised words*, but on the test
  device the recogniser reported constant activity while transcribing nothing —
  empty results and a session ending every second or two. So in a noisy room,
  or with a child who mumbles, the timer never started and the mic sat open
  until the 45-second cap. It is now armed by any sign of life: four seconds of
  quiet once there are words to answer, twelve seconds when nothing has been
  understood, after which the mic closes quietly and says nothing.

### Notes
- Found by tracing on the device rather than by reasoning: the trace showed
  `onResult` firing with empty words, and the failure printing the offending
  request body with a ☀️ in it.
- Both fixes are guarded by tests confirmed to fail against the old code. The
  first attempt at the encoding test passed against the bug, because reverting
  half the fix left the charset header in place — either half alone is enough.
- The connection-pool fix in 1.18.1 was a real leak and worth keeping, but it
  was not the cause of this.
- `flutter analyze`: 0 issues; 92/92 tests.

---

## [1.18.1] — 2026-08-10

### Fixed
- **Pollie worked for a while and then failed for good**, saying "Oops, I got
  lost for a moment!" to everything. Every message built a brand-new HTTP
  client with its own connection pool, and never closed any of them. A long
  chat exhausted the phone's sockets, and from that point every request failed
  for the rest of the session. There is now one client per session, closed when
  the screen is left.
- **The microphone waited for a button press.** A turn only ended when the mic
  was tapped again, which means a four-year-old had to know to press a button
  to be answered. The turn now ends by itself after four seconds of quiet —
  long enough to think mid-sentence, which is what the original half-second
  cut-off got wrong.
- **A one-minute pause was reported as the day being over.** Google's free tier
  limits requests per minute *and* per day and returns the same code for both;
  the proxy called every one of them "out of words for today", telling a child
  to come back tomorrow when the answer was thirty seconds away. The two are
  now told apart, and a brief pause says so and leaves Pollie awake.

### Changed
- The proxy retries once when Gemini returns a 5xx. A model that is briefly
  overloaded used to end the conversation.

### Notes
- The connection-pool fix is guarded by a test that counts clients: 50 turns
  used to build 50 clients, and now build one. A plain "50 requests succeed"
  test passed against the broken code, because a test machine has sockets to
  spare — it proved nothing.
- Measured through the deployed proxy: replies in 0.7 s.
- `flutter analyze`: 0 issues; 91/91 tests.

---

## [1.18.0] — 2026-08-10

### Added
- **Pollie works for everyone.** The proxy is deployed, and the app now ships
  pointing at it, so anyone who installs the app can talk to Pollie without an
  API key of their own. Measured end to end: a reply in about 0.6 seconds.

### Fixed
- **The proxy's model was wrong in two ways.** It pinned `gemini-2.5-flash`
  with `thinkingConfig: { thinkingBudget: 0 }`. That model is no longer served
  to new API keys at all, and `thinkingBudget` is rejected as an invalid
  argument by every current model — so every request failed. It now uses the
  `gemini-flash-lite-latest` alias with no thinking config: measured at ~600 ms
  against full flash's ~1800 ms, which suits two short sentences to a
  four-year-old.
- **The proxy hid why requests failed.** Every upstream error came back as a
  bare "unreachable", which made a misconfigured key indistinguishable from a
  retired model. It now reports the status and message Google gave.

### Changed
- The app sends its own `User-Agent`. Cloudflare rejects clients that look
  automated with error 1010; Dart's default passes today, but saying who we
  are is less fragile.
- `CompanionScreen` accepts an injected `PollieService` so tests can build an
  unconfigured Pollie — now that the shipped default is a working proxy.

### Notes
- An alias rather than a version pin, because the pin is exactly what broke:
  models are retired faster than a toddler app gets rebuilt. Changing it is a
  Worker deploy, not an app release.
- `worker/README.md` gained the two setup traps we hit: a brand-new
  `workers.dev` subdomain has no certificate for a few minutes, and pasting the
  key at the wrong prompt stores it as the secret's *name*, where it is not
  hidden.
- `flutter analyze`: 0 issues; 88/88 tests.

---

## [1.17.0] — 2026-08-10

### Added
- **Six more animals in "Which Animal?"**: 🐻 bear, 🐧 penguin, 🐭 mouse,
  🐦 bird, 🐷 pig and 🐯 tiger. Fifteen animals in total, up from nine.

### Improved
- **New recordings for cat, cow, horse, chicken, lion, monkey, elephant and
  frog**, all supplied from Pixabay. The monkey no longer opens with birdsong,
  and the horse and frog are no longer the low-bitrate Commons files.

### Changed
- **"Which Animal?" is no longer limited to the shared animal list.** Animal
  Food needs a food for every animal it uses; a listening game does not, so
  requiring one meant a tiger could not have a roar until someone invented its
  dinner. 🐷 🐦 🐯 exist only in this game. The test that guarded against typos
  now checks for duplicates and for consistent emoji instead.
- The audio pipeline's gain and limiting ceilings for animal calls were
  loosened, now that the sources are stock-library rather than field
  recordings. All fifteen sit within about 2 dB of each other.

### Notes
- 🐘 the elephant's new source is 11 kHz, noticeably lower fidelity than the
  rest. It was kept because it is the *right* sound, which is what was asked
  for, but it is the one to replace if a better recording turns up.
- 🦒 the giraffe and 🐰 the rabbit still have no call; neither makes a sound a
  child would recognise.
- `flutter analyze`: 0 issues; 88/88 tests.

---

## [1.16.0] — 2026-08-10

### Fixed
- **Animals vanished from Find It!** — and reappeared only while the back
  gesture was held. The card scaled up when tapped correctly, and animating a
  scale over text re-rasterises the emoji glyph every frame until the raster
  cache gives up and stops drawing them; holding back forced a repaint, which
  is why they flickered back. This project already had the rule written down
  after the jigsaw hit it. Four places were breaking it: Find It!, Count the
  Animals!, Memory Match and Bubble Pop's pop-sparkle, which scaled on every
  frame of every pop. All four now use rotation, padding or translation, none
  of which re-rasterise.
- **Find It! had no sound for a correct answer.** Every other game popped; it
  was the one that never did.

### Added
- **Stars for Jigsaw, Animal Food and Bubble Pop.** Not intentional — they
  simply had nothing to score. The drag games now count pieces dropped on the
  wrong slot; Bubble Pop, which has no wrong move, scores on the clock left.
- Every game mode now has both sounds: a pop for right, a "tetot" for wrong.

### Changed
- **Memory Match no longer locks the whole board while a pair resolves.** Turn
  two cards, and while they are still showing you can start the next pair. Only
  the cards in a resolving pair are locked, not everything.

### Notes
- The rasterisation trap is now the *first* golden rule in CLAUDE.md, since it
  has now caused a visible bug twice.
- `flutter analyze`: 0 issues; 87/87 tests. Both the memory-concurrency and the
  repeat tests were confirmed to fail against the code they fix.

---

## [1.15.0] — 2026-08-10

### Fixed
- **Games asked for the same animal twice.** Which Animal? and Find It! only
  avoided repeating the *previous* round's animal, so a five-round game could
  ask for the monkey twice — wasting a round and reading, correctly, as a bug.
  Both now remember every animal asked this game. Bubble Pop also no longer
  shows two bubbles wearing the same face at once.
- **The monkey opened with a bird.** It was a Vervet Monkey field recording
  whose own description said "against a background of birds", which I should
  have read. It is now a chimpanzee pant-hoot — the call a child actually
  associates with a monkey.

### Added
- **🐮 The cow.** It took five searches. Wikimedia Commons has no moo at all
  under any licence — every hit is the *word* "cow" in some language, a gospel
  song, or a fart — so it comes from a CC0 sound-effects library on the
  Internet Archive instead.

### Improved
- **A far better elephant**, from the same CC0 library: a clean close-miked
  trumpet that needed no gain at all, where the old one needed +9 dB and
  crackled for it.

### Notes
- Nine animals now: 🐱 🐶 🐮 🐴 🐔 🦁 🐵 🐘 🐸.
- Both repeat tests were confirmed to fail against the unfixed code — the
  Which Animal? one fails with "asked for one of [🐔, 🐱, 🐵, 🐮, 🐵] twice",
  which is exactly the reported symptom.
- Writing those tests turned up something else: at flutter_test's default
  600px-tall viewport, the five-card grid scrolls and its bottom row cannot be
  tapped, so the game cannot be played through at all. Real phones are tall
  enough, but every game test that taps now runs at phone size.
- 🐴 the horse is the last weak one. Its source is ~60 kbps and it stays
  quieter than the rest, because lifting it to match puts the crackle back.
- `flutter analyze`: 0 issues; 86/86 tests.

---

## [1.14.0] — 2026-08-10

### Added
- **🐵 The monkey**, and a proper **Credits screen** (ℹ️, top-left of the home
  screen) naming every animal recording and its author.
- CC BY recordings are now allowed alongside CC0 and public domain — never
  ShareAlike, which would reach into the app itself. That licence is what the
  credits screen pays for, and it is what made the next two entries possible.

### Improved
- **A much clearer cat.** The old one was a Siamese; the new one is an
  uncompressed recording of a British Shorthair asking for food — an
  unmistakable *miaow*, which is what was asked for.
- **A much better lion**, from a 68 kbps recording to a 256 kbps one.

### Notes
- 🐮 the cow is still missing, and not for want of looking. Four searches of
  Commons return Lingua Libre recordings of people pronouncing the word "cow",
  a gospel song, and one fart. There is no moo on Commons under any licence we
  can ship. A phone held over a fence would beat everything available.
- 🐴 the horse and 🐘 the elephant did not improve either: CC BY adds nothing
  better than what they already had.
- A test asserts every bundled call has a credit entry, and that no credit
  names a ShareAlike licence. A sound shipping uncredited is a licence breach,
  not a typo.
- `flutter analyze`: 0 issues; 84/84 tests.

---

## [1.13.0] — 2026-08-10

### Fixed
- **The music kept dying mid-game and never came back.** Every player in
  `audioplayers` asks Android for `AudioFocus.gain` by default — an
  *exclusive* request. So each bubble pop, each fanfare and each animal call
  told the system to stop other audio, and the system duly stopped our own
  music. It died fastest in Bubble Pop, where the taps come quickest, and it
  stayed dead after a win. Nothing in this app should be taking focus from
  anything else in it, so nothing does now.
- **Music could get stuck quiet.** The duck under a win or lose sound was
  released by the clip's completion event alone; if that event was ever
  missed, the music stayed at a third of its volume for the rest of the
  session — indistinguishable from broken. A timer backs it up now.
- **The animal calls crackled.** Two causes, both mine: the pipeline let the
  limiter work as hard as it liked, and waveshaping a transient that hard *is*
  the crackle; and it lifted quiet sources by up to 14 dB, which amplifies a
  60 kbps recording's noise floor rather than the animal. Field recordings now
  get stricter gain and limiting ceilings than studio material does.

### Added
- **🐶 The dog.** A CC0 bark finally turned up, so the animal a toddler knows
  best is in "Which Animal?" at last.
- **A "tetot" on a wrong answer**, in every game that has one: Find It!, Count
  the Animals!, Memory Match, Which Animal?, and both drag games. Two soft
  descending tones — it should correct, not scold, so it is quieter than the
  pop and deliberately not a buzzer.
- **The pop now confirms a correct placement** in the Jigsaw and Animal Food,
  which had no sound at all when a piece went home.

### Changed
- **Music plays in every game.** "Which Animal?" turns it down to a third
  rather than off, because a game that falls silent reads as broken.
- **A much better rooster**: the previous crow was a 116 kbps Ogg, the new one
  an uncompressed CC0 recording.

### Notes
- In the drag games the "tetot" fires only for a piece dropped **onto the
  wrong slot**. Letting go over empty space is a change of mind, and buzzing
  at that would punish a child for thinking.
- 🐴 the horse and 🐘 the elephant stay noticeably quieter than the rest. Their
  sources are the best free ones in existence and both are around 60–100 kbps;
  lifting them to match would put the crackle straight back. 🐮 the cow still
  has no usable free recording at all.
- `flutter analyze`: 0 issues; 81/81 tests.

---

## [1.12.1] — 2026-08-10

### Fixed
- **Animal Food's food boxes hung off the screen.** The slot size was worked
  out from the available width without paying for the gaps between columns, so
  the board came out `(columns - 1) × gap` — 48 px — wider than the space it
  had, and the outer boxes sat past both edges at every level.
- **On Big, the food names landed on top of the animals.** A caption hangs in
  the gap *beneath* its slot, and the layout never reserved that gap for the
  bottom row, so the last row's words ran into the drawer.
- **Four headers overflowed on a 360 dp phone.** Animal Food, Memory, Jigsaw
  and Bubble Pop centred their titles with `Spacer`s, which cannot give back
  space they do not have. They now use `Expanded`.
- **The music kept playing when the phone was locked.** The games paused their
  clocks on background, but nothing told the music. It pauses now — and
  resumes where it left off rather than restarting the theme.

### Improved
- **The animal calls sound much better.** They were encoded at 22.05 kHz from
  44.1 kHz sources, throwing away everything above 11 kHz — that is what made
  them muffled — and at 64 kbps with up to 8× gain, which amplified the noise
  floor. Now 44.1 kHz at 96 kbps.
- **Every sound in the app is at one level.** Music, effects and animal calls
  came from three different mastering processes and differed by more than
  20 dB, so the music drowned the pop and a call could arrive inaudible or
  startling. All of it is normalised to −16 dBFS RMS by the new
  `tool/normalize_audio.py`, within 0.2 dB of each other. Player volumes now
  mean something instead of compensating for unknown file levels.

### Added
- `tool/normalize_audio.py` — the audio build step, with the loudness targets
  and the reasoning written down.
- Layout tests that build every screen at 360 dp. `flutter_test` fails on
  overflow, so this is what caught the four broken headers; at the default
  800×600 test viewport they all fit and nothing ever complained.

### Notes
- `pop.wav` is deliberately left ~3 dB under the rest: it is a 0.12 s
  transient, and matching a click's average level to a sustained sound makes
  the click feel louder rather than equal.
- `flutter analyze`: 0 issues; 76/76 tests. The layout tests were confirmed to
  fail against the unfixed code.

---

## [1.12.0] — 2026-08-10

### Added
- **Which Animal? 🔊** — a seventh game. A big speaker button plays an animal's
  call and the child taps who made it: 2 choices on Easy, 3 on Medium, 5 on
  Big. The sound replays as often as they like; re-listening is the skill the
  game is for, not a way around it.
- `ASSET_CREDITS.md` — where every bundled sound came from and under what
  licence.

### Notes
- **Only six animals have a call**: 🐱 🐴 🐔 🦁 🐘 🐸. Every recording is CC0 or
  public domain from Wikimedia Commons, trimmed to its loudest ~2 seconds,
  normalised and encoded as mono AAC — about 18 KB each.
- **🐮 the cow and 🐶 the dog are missing**, which is a real gap: they are the
  two animals a toddler knows best. No CC0 or public-domain recording of
  either could be verified. Searching turns up plenty of *Lingua Libre* files —
  humans pronouncing the word "cow" — which is exactly the trap this game must
  not fall into. Closing the gap needs either free recordings or accepting
  CC-BY material and shipping a credits screen.
- The calls play through their own audio player. `pop()` stops its player
  before every play, so sharing one would let a stray tap cut a call short —
  and the call *is* the puzzle.
- `flutter analyze`: 0 issues; 65/65 tests.

---

## [1.11.0] — 2026-08-10

### Fixed
- **Pollie stops cutting the child off mid-sentence.** A recogniser session
  ending is no longer the turn ending: its words are banked and the
  microphone re-arms. The turn now ends when the child taps the mic, after
  45 seconds, or on a real error — not when Android decides half a second of
  silence means "finished".

### Security
- **The Gemini API key no longer ships inside the APK.** It was compiled into
  `libapp.so` as a plain string, where `strings libapp.so | grep AIza` finds
  it in seconds — and the signed APK is attached to public releases, so the
  private repo never protected it. A Cloudflare Worker (`worker/`) holds the
  key now; the app ships only a URL, which is not a secret. **The old key must
  be rotated**, because every APK ever released still carries it.
- Each install sends a random per-launch id so the proxy can rate limit. It
  identifies nothing about the child and nothing is written to disk.

### Improved
- **Pollie answers much faster, especially far from Google's servers.** Three
  things were stacked: the model was thinking before every reply, the whole
  reply was generated before a single word was spoken, and the round trip was
  long. Thinking is off, Pollie now speaks each sentence as it arrives instead
  of waiting for the last one, and the proxy shortens the trip.

### Added
- **Pollie is alive.** She bobs on the home screen and says "Tap to talk! 💬"
  after a few seconds — nothing else on that screen told a grown-up the bird
  was a button. On her own screen she leans in while listening and nods while
  speaking.

### Removed
- `google_generative_ai`. It is discontinued, and it cannot express
  `thinkingConfig` at all, which is what made every reply slow. Replaced by a
  small HTTP client — one dependency fewer, not one more.

### Notes
- The turn rework was tried once before and reverted, because
  `onResult(finalResult: true)` and `onStatus('done')` both fire for one
  session ending and both restarted the mic, racing into "recognizer busy".
  A single-flight guard is the piece that was missing.
- The model is pinned to `gemini-2.5-flash` **in the Worker**, because
  `thinkingBudget: 0` does not exist on 3.x Flash and the `-latest` alias
  would have silently gone slow again. Changing it is now a deploy, not a
  release.
- `KidSafety` still guards input and output in the app. A proxy the app trusts
  is not the same as a guard the child is behind.
- `flutter analyze`: 0 issues; 58/58 tests.

---

## [1.10.0] — 2026-08-10

### Added
- **Every game is now timed.** 30 seconds on Easy, 1 minute on Medium,
  2 minutes on Big — one clock for the whole game. The countdown is a bar that
  shrinks and turns green → amber → red, with no digits: the child it is for
  cannot read a clock, so the colour has to carry it. Under ten seconds it
  pulses and a ⏰ appears.
- **You can lose.** Running out of time ends the game with a "Time's up!"
  screen, the lose sound, and Try again / Home.
- **Bubble Pop has levels** at last: 6, 8 or 12 bubbles.

### Changed
- **The clock starts on the first move, not when the screen opens.** A child
  looking at a fresh board should not be losing time before touching anything.
- **Count the Animals and Find It ask 3 rounds on Easy** instead of 5. Five
  rounds inside a 30-second clock is six seconds a question, which a
  four-year-old will not make. Medium and Big stay at 5.
- **Bubble Pop is one timed round instead of endless escalating ones.** A game
  with no finish line has nothing for a countdown to run out against, so the
  speed-up now happens inside the round: the closer to done, the faster the
  bubbles drift.

### Notes
- The clock pauses when the app goes to the background, and stops the instant a
  game is won — a timeout must never land on top of a celebration. Where a win
  is animated (Bubble Pop's 400 ms pop, the 350 ms round advance), the clock
  stops when the win is *decided*, not when its overlay appears.
- `TimedGame` carries all of this so seven screens do not each grow a copy.
- `flutter analyze`: 0 issues; 45/45 tests.

---

## [1.9.0] — 2026-08-10

### Added
- **Background music.** A main theme on the home and level screens, and a
  game song in the games. Both loop. Pollie's screen stays silent — music
  there would fight her voice and her microphone would hear it.
- **A music button** (🔊 / 🔇) in the top-right of the home screen, for the
  car, the waiting room and the nap. The choice lasts as long as the app is
  open; nothing is written to disk, because nothing about this app is.
- **Finish sounds.** Three stars get their own fanfare, one and two stars get
  another, and there is a sound for running out of time — used by the game
  timers in a later release. The music ducks underneath so the fanfare is
  audible over it.

### Notes
- Music is looped by `MusicService`, deliberately separate from
  `SoundEffects`: that class stops its player before every play so rapid taps
  re-pop cleanly, and one shared player would let every pop kill the music.
- Track switching runs through a `NavigatorObserver` rather than each screen's
  `initState`. Popping a game does not re-run `HomeScreen.initState`, so
  per-screen calls would leave the game song playing over the menu.
- The two Suno tracks were re-encoded from 192 kbps stereo to mono AAC, taking
  the bundle from 5.3 MB to 2.7 MB. Through a phone speaker, under gameplay,
  the difference is not there.
- Background music was tried once before and removed for sounding bad. That
  version was synthesised by a tool in this repo; these are composed tracks.
- `flutter analyze`: 0 issues; 36/36 tests.

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
