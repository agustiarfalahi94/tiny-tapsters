# Pollie: speech cutoff, latency, key safety, animation

Branch: `feat/pollie` → v1.10.0

Four related problems in one branch, because three of them touch the same two
files and shipping them separately means three rounds of device testing on the
one phone that can reproduce the speech bug.

## 1. Pollie cuts the child off after ~500 ms of silence

### Root cause (confirmed, not inferred)

`speech_to_text` 7.4.0's Android implementation builds its recognizer intent in
`SpeechToTextPlugin.kt:654-698`. It sets exactly one silence-related extra:

```kotlin
pauseFor?.also {
    putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, it)
}
```

It never sets `EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS` or
`EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS`. The "possibly complete" timer
defaults to roughly 500 ms on most Android recognizers and fires
`onEndOfSpeech` → final result → the plugin reports `finalResult: true`, which
`companion_screen.dart:341` treats as the end of the turn.

So `pauseFor: 3s` is being honoured and is simply the wrong timer. The comment
at `companion_screen.dart:87` — "a much shorter 'possibly finished' one we
cannot configure at all" — is correct about the timer and wrong that it cannot
be configured. It can, just not through this plugin's Dart API.

### Fix, part A: patch the plugin

Vendor `speech_to_text` 7.4.0 into `packages/speech_to_text/` as a path
dependency in `pubspec.yaml`. The patch is confined to the Android plugin and
the Dart options class:

- `SpeechListenOptions` gains `Duration? possiblyCompleteSilence` and
  `Duration? minimumLength`, passed down the existing method channel alongside
  `pauseFor`.
- `setupRecognizerIntent` sets the two extras when provided, and includes them
  in the `previous*` comparison that decides whether the intent needs rebuilding
  — otherwise a changed value is silently ignored.

`packages/speech_to_text/PATCH.md` records the upstream version, the exact
diff, and why, so a future upgrade is a mechanical re-apply rather than an
archaeology exercise.

Values used by the app: `possiblyCompleteSilence: 2500ms`,
`pauseFor: 4000ms`, `minimumLength: 3000ms`. Long enough for a toddler to
think mid-sentence, short enough that the turn still ends on its own if the
mic button is never tapped.

### Fix, part B: a turn stops being one recognizer session

Patched extras are advisory — some OEM recognizers (Samsung's, and reportedly
some HyperOS builds) ignore them. So the turn model changes too:

- A recognizer session ending no longer ends the turn. Its words are banked
  into `_heard` and the session is re-armed.
- The turn ends only on: the mic tapped again, the 45 s `_maxTurn` cap, a
  non-recoverable speech error, or app backgrounding.
- A single-flight `bool _restarting` guard makes the restart idempotent.
  This is what the previous attempt was missing: `onResult(finalResult: true)`
  and `onStatus('done')` both fire for one session ending, and both called
  restart, racing into "recognizer busy". Only the first caller to flip
  `_restarting` proceeds; it clears the flag once `listen()` resolves.

The comment block at `companion_screen.dart:84-107` gets rewritten. It
currently instructs future readers *not* to reintroduce a restart loop. That
advice was right given an unpatched plugin — restarting to dodge a 500 ms timer
loses more speech to the ~300 ms restart gap than it saves. With the extras
patched, sessions rarely end mid-sentence, so restarts become rare recovery
rather than a constant treadmill. The new comment must say exactly that, or
someone will revert this on the strength of the old comment.

## 2. Slow replies (reported from Indonesia)

Three stacked causes:

1. **Thinking tokens.** `_modelId = 'gemini-flash-latest'` resolves to a
   thinking model, and `maxOutputTokens: 800` is shared between thinking and
   output — so every reply pays a full reasoning pass before the first token.
   For "Pollie says two friendly sentences to a four-year-old" this is pure
   latency.
2. **TTS waits for the whole stream.** `companion_screen.dart:485-522` streams
   into a buffer and only calls `_speak(reply)` after the stream completes. The
   child waits for full generation *and then* full synthesis.
3. **Round trip to Google's endpoint** from Indonesia.

### Fixes

- Disable thinking via `generationConfig.thinkingConfig.thinkingBudget: 0`.
  This works on Gemini **2.5** Flash and is *not* available on 3.x Flash, so
  the model gets pinned to `gemini-2.5-flash` rather than the `-latest` alias.
  The pin lives in the Worker (§3), so switching models later — including to a
  3.x model with `thinkingLevel` instead — needs no app release.
- `maxOutputTokens` drops to 200. Without thinking tokens competing for the
  budget, 200 is generous for 2–3 short sentences, and a smaller cap means the
  stream finishes sooner.
- **Speak sentence by sentence.** As chunks arrive, split the buffer on
  sentence-ending punctuation and hand each complete sentence to `flutter_tts`
  as soon as it lands, queueing the rest. `flutter_tts` has
  `setQueueMode(1)` (add-to-queue) on Android for exactly this. Pollie starts
  talking after the first sentence instead of after the whole reply — roughly
  halving perceived latency on its own, before the network improves.
  - `_cleanForSpeech` runs per sentence rather than once at the end.
  - The completion handler that re-arms the mic must fire after the *last*
    sentence, not the first: track a pending-sentence count and only
    `thenListen` when it reaches zero and the stream is closed.
- Edge routing via the Worker (§3) shortens the Indonesia round trip.

## 3. The API key ships inside the APK

`String.fromEnvironment('GEMINI_API_KEY')` is compiled into `libapp.so` as a
plain string. `strings libapp.so | grep AIza` recovers it in seconds. The
private repo does not protect it, because the signed APK is attached to public
GitHub releases. Every install also shares one free-tier quota, which is why
two people using Pollie compete for it.

### The proxy

A Cloudflare Worker in `worker/`:

```
worker/
  src/index.ts       # the proxy
  wrangler.toml
  package.json
  README.md          # account setup + deploy, written for a first-time user
```

Behaviour:

- Accepts `POST /chat` with `{ messages: [{role, text}...] }`.
- Rejects anything else, and any request without a valid `X-Install-Id` header
  (a UUID the app generates on first run).
- Calls Gemini `streamGenerateContent` with the key from
  `env.GEMINI_API_KEY` (a Worker secret, never in `wrangler.toml`), pinning
  `gemini-2.5-flash`, `thinkingBudget: 0`, `maxOutputTokens: 200`, and the same
  four `safetySettings` at `BLOCK_LOW_AND_ABOVE` that
  `pollie_service.dart:125` uses today.
- Streams the response straight back to the app.
- Rate limits per install id using a Cloudflare rate-limiting binding:
  30 requests/minute and a daily ceiling, so one user cannot drain the shared
  quota. Over the limit returns 429, which the app already knows how to show as
  "Pollie is all out of words for today".
- The system prompt moves server-side. It stops being a thing an APK inspector
  can read and rewrite, and it becomes editable without an app release.

The Worker free tier is 100k requests/day and needs no card.

**The user runs these** (interactive, and they involve the real key):

```bash
npx wrangler login
npx wrangler secret put GEMINI_API_KEY
npx wrangler deploy
```

### App side

`pollie_service.dart` drops `google_generative_ai` — the package is
discontinued and cannot express `thinkingConfig` at all — for a small REST
client over `dart:io` `HttpClient`, hitting the Worker. This removes a
dependency rather than adding one.

- Endpoint from `--dart-define=POLLIE_ENDPOINT=...`, with the deployed URL as
  the compile-time default. A URL in the APK is not a secret.
- Install id: a v4 UUID generated with `Random.secure()` on first run. **No
  persistence available** (no `shared_preferences` by decision in the audio
  spec), so it is generated once per app launch and held in memory. That is
  enough for rate limiting — it bounds a single session's burst — and it stores
  nothing about the child, which suits an app that promises no tracking.
- `PolliePing`, `quotaResetLabel()` and the whole quota-notice UI stay; the
  Worker returns 429 with a `retry-after` the app maps onto the existing
  "out of words" bubble.
- `KidSafety` guards on input and output stay exactly where they are. The
  Worker is not a trusted replacement for them.

**CI:** `.github/workflows/release-apk.yml` stops needing `GEMINI_API_KEY` and
passes `POLLIE_ENDPOINT` instead. The repo secret should be deleted from
GitHub *after* the Worker is live, and the old key **rotated in Google AI
Studio**, because every APK ever released still carries it.

## 4. Pollie should look alive and invite conversation

- **Home screen.** The 🦜 FAB gets a continuous gentle bob (a ~2.4 s
  `AnimationController`, ±4 px vertical, slight rotation) plus a speech bubble
  reading "Tap to talk! 💬" that fades in about 3 s after the home screen
  settles and stays. Toddlers cannot read it — it is aimed at the parent, and
  the motion is what the child reads.
- **Companion screen.** The existing status face already changes per state
  (`_statusFace`). Add motion on top: idle bob when awake, a forward lean and a
  scale pulse tied to `_soundLevel` while listening (the mic pulse exists — the
  bird should share it), and a small nodding motion while speaking.
- All animations use a single `AnimationController` per screen driving an
  `AnimatedBuilder` around the emoji `Text`. No new dependency.

**Golden rule 3 applies:** never swap widget types mid-gesture. These are
`Transform`/`AnimatedBuilder` wrappers around a stable subtree, and the
companion screen has no drag gestures, so there is no interaction to cancel.

## Testing

- Sentence splitter: handles `.`/`!`/`?`, decimals, ellipses, an unterminated
  trailing fragment, and Indonesian text.
- Restart guard: two concurrent restart requests result in one `listen()` call.
- A turn survives a session ending, and banks that session's words.
- REST client: request body shape, `X-Install-Id` present, 429 → quota state,
  network error → the existing "got lost for a moment" bubble.
- Worker: unit tests for method/header rejection and rate-limit behaviour.
- Manual device test on the Xiaomi 15 for the actual cutoff — no unit test can
  confirm the recognizer extras took effect.

## Risks

- Some OEM recognizers ignore the silence extras. Mitigated by fix 1B, which
  works regardless. If both fail on a given device, the mic button still ends
  the turn correctly and the behaviour is no worse than today.
- Vendoring a plugin means it no longer updates with `pub upgrade`. `PATCH.md`
  and a pinned upstream version are the mitigation. Worth it: the alternative
  is a bug the user has now reported twice.
- Pinning `gemini-2.5-flash` means eventual retirement. Because the pin is in
  the Worker, that is a one-line server change, not an app release.

## Out of scope

- Persisting the install id (needs a storage dependency).
- Voice selection changes — the existing `pickBestVoice` logic stays.
- Authenticating installs. Rate limiting is proportionate for a family app.
