# Vendored packages, and exactly what was changed

Two packages are copied in here rather than pulled from pub, because the app
needs an Android setting neither exposes. Everything else is upstream and
untouched.

| Package | Upstream version |
|---|---|
| `speech_to_text` | 7.4.0 |
| `speech_to_text_platform_interface` | 2.4.0 |

`example/`, `test/` and `.dart_tool/` were dropped; nothing else was removed.
Every change is marked in the source with `TINY TAPSTERS PATCH`.

There are two patches, applied at different times for different reasons.
Patch 1 made the recogniser stop ending sessions mid-sentence. Patch 2 took
endpointing away from the package entirely and gave the app a signal it never
had: when the microphone is actually recording.

---

# Patch 1 — the two silence extras (v1.10.0)

## Why

Android's recogniser has **two** silence timers:

- a long "definitely finished" one, exposed by the package as `pauseFor`
- a short "probably finished" one, about **half a second** on most devices

The short one is not settable through the published package at all. Half a
second is shorter than the pause between words in a sentence, so it ends the
recognition session mid-sentence. Every restart leaves a gap of tens of
milliseconds in which nothing is captured, and words spoken in that gap are
lost. On the test device, sessions were ending **every one to two seconds**.

That is what made Pollie cut a child off, and later what turned
"do you know about minecraft?" into "know minecraft".

Android does expose the setting, as intent extras:

- `EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS`
- `EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS`

The package simply never sets them.

## The change

**`speech_to_text_platform_interface`**

- `SpeechListenOptions` gains `possiblyCompleteSilence` and `minimumLength`,
  both `Duration?`, both included in `copyWith`.
- `method_channel_speech_to_text.dart` sends them in the `listen` arguments.

**`speech_to_text` (Android only)**

- `SpeechToTextPlugin.kt` reads the two arguments, threads them through
  `startListening` and `setupRecognizerIntent`, and sets the two intent extras.
- They also join the `previous*` comparison that decides whether the intent
  needs rebuilding — without that, a changed value is silently ignored.

iOS, macOS and web are untouched; the options are Android-only and default to
null, so behaviour elsewhere is exactly upstream.

---

# Patch 2 — the app owns endpointing (v1.25.0)

Patch 1 stopped sessions ending *too early*. It did not stop three other things
from ending them, and it could not tell the app when recording actually began.

## Why: `pauseFor` is not a silence timer

`pauseFor` looks like "stop after N ms of silence". It is not. Passing it arms a
Dart-side timer in `speech_to_text.dart` (`_setupListenAndPause` →
`_stopOnPauseOrListen`) that calls `_stop()` when `_elapsedSinceSpeechEvent`
exceeds it — and `_lastSpeechEventAt` is updated only inside `_notifyResults`,
only when the recognised **text changes**.

So `pauseFor: 3s` means "stop three seconds after the transcript last moved".
A child who is still talking while the recogniser's guess happens to be stable
gets the session pulled out from under them, and the words spoken during the
restart are gone. That is what turned "in minecraft how do you create a tnt?"
into "in minecraft how do you".

`pauseFor` is also the source of the `EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS`
intent extra, so it could not simply be dropped — losing the Dart timer meant
losing the native one too. **`completeSilence` splits them.** The app now passes
`pauseFor: null` (no Dart timer) and `completeSilence` (native timer only), and
does its own silence detection from the sound-level stream.

## Why: `listening` does not mean the microphone is on

`startListening` calls `notifyListening(isRecording = true)` and
`result.success(true)` on the calling thread — **before** the `handler.post` that
runs `speechRecognizer.startListening()` has executed, and long before the
recognition service has opened `AudioRecord`. Android does provide the real
signal, `onReadyForSpeech`, and the package overrode it with an empty body.

Now it is forwarded as the status string `readyForSpeech`. The app shows the
child a "go" cue only when this arrives, so nobody talks into a mic that is not
yet recording. Nothing may *depend* on it: iOS, macOS and web have no
equivalent, and an OEM Android may not emit it, so the app also proceeds on a
timeout.

## The change

**`speech_to_text_platform_interface`**

- `SpeechListenOptions` gains `completeSilence` (`Duration?`), in the
  constructor **and `copyWith`** — `listen()` re-copies the options, so a
  `copyWith` that forgets a field silently discards it.
- `method_channel_speech_to_text.dart` sends it. Nothing was needed for
  `readyForSpeech`: `notifyStatus` already forwards arbitrary strings, which is
  why this is a status string rather than a fourth callback.

**`speech_to_text` (Dart)** — patched for the first time in Patch 2.

- `readyStatus` constant, `_micReady` flag, `isMicReady` getter.
- `_onNotifyStatus` gains a `case readyStatus:` that **returns early**. This is
  the load-bearing line: falling through to
  `_listening = status == listeningStatus;` would set `isListening` to *false*
  while the mic is hot, which silently kills `_onSoundLevelChange` and every
  `isListening` guard in callers.

**`speech_to_text` (Android)**

- `SpeechToTextStatus.readyForSpeech` appended to the enum (transported by
  `.name`, so ordinals do not matter).
- `onReadyForSpeech` implemented, guarded by `if (!listening) return` so a stale
  callback from an abandoned session cannot re-open the caller's gate.
- `completeSilence` threaded through `onMethodCall` → `startListening` →
  `setupRecognizerIntent`, including the `previous*` rebuild comparison.
- The long-silence extra now reads `completeSilence ?: pauseFor`, so an
  unpatched caller is bit-identical to upstream.
- `onEndOfSpeech` reads `previousCompleteSilence ?: previousPauseFor ?: 1000`.
  That timer is a **fourth, undocumented endpointer**: it fires
  `notifyListening(false)` after the delay. Left alone, `pauseFor: null` would
  have collapsed it to a hard one-second cut-off — shorter than the pause
  between a child's words, and worse than upstream.

## What Patch 2 deliberately does NOT do

Recorded so the next person does not re-investigate:

- **`EXTRA_SEGMENTED_SESSION`** (continuous/long-form recognition, API 31+).
  It would remove restart gaps entirely rather than making them rare, but OEM
  support is uneven and it needs a fallback path. Considered and deferred.
- **The `startListening` thread ordering.** Moving `notifyListening(true)`
  inside the `handler.post` would change `isListening` timing for every
  consumer. Forwarding `onReadyForSpeech` makes the ordering irrelevant, which
  is the cheaper fix.
- **`isDuplicateFinal`** (drops finals arriving within 100 ms of each other).
  The app is immune instead: it banks partials on every session end and never
  depends on receiving a final, so a dropped one costs nothing.
- **`speechThresholdRms`** (rewrites `ERROR_NO_MATCH` to `ERROR_SPEECH_TIMEOUT`
  below RMS 9). Both strings hit the same "quiet error" branch in the app.

## Upgrading

The two patches are about forty lines across four files. To move to a newer
upstream:

1. Copy the new version over the top, minus `example/`, `test/`, `.dart_tool/`.
2. Search the old copy for `TINY TAPSTERS PATCH` and re-apply each block.
3. Check `setupRecognizerIntent` still guards on the `previous*` values.
4. Check `onEndOfSpeech`'s timer still reads the `completeSilence` fallback
   chain, or `pauseFor: null` becomes a one-second cut-off.
5. Check `_onNotifyStatus` still **returns** for `readyStatus` before
   `_listening = status == listeningStatus;`. A new upstream arm could swallow
   it or reintroduce the flip.
6. Run `flutter test test/speech_plugin_test.dart` — unlike Patch 1, Patch 2 is
   unit-testable, and those tests fail loudly if any of the above regresses.
   Then still test on a real phone: the intent extras themselves cannot be
   verified off-device.

Check first whether upstream has added these options — if so, drop the fork and
go back to pub.

## Analysis

`analysis_options.yaml` excludes `packages/**`. This is upstream code; we
maintain a patch, not its style.
