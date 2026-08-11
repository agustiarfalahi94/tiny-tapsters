# Pollie's microphone: why it cut children off, and what replaced it

Branch: `feature/pollie-mic-v2` → v1.25.0

Four symptoms were reported from real use on the Xiaomi 15:

1. The first one or two words are cut — **not on the first turn**, but from the
   second or third onward.
2. A dead gap between Pollie finishing speaking and the microphone activating.
3. Mid-utterance loss: *"in minecraft how do you create a tnt?"* → *"in
   minecraft how do you"*.
4. Short answers like *"yes"* need four or five attempts.

They are not four bugs. They are one design failure — **nothing in the stack was
measuring silence, and nothing knew when the microphone was actually on** —
expressed through five distinct mechanisms, all confirmed in source.

## The five mechanisms

### 1. `pauseFor` is not a silence timer

`speech_to_text.dart:563,576-588` arms a Dart-side timer that calls `_stop()`
when `_elapsedSinceSpeechEvent` exceeds `pauseFor`. `_lastSpeechEventAt` is
updated only inside `_notifyResults`, and only when the recognised **text
changes** (`:679-683`).

So `pauseFor: 3s` means *"stop three seconds after the transcript last moved"*.
A child who is still talking while the recogniser's guess happens to be stable
has the session pulled out from under them, and the words spoken during the
restart are gone. This is symptom 3.

### 2. Every Android speech error is reported as permanent

`SpeechToTextPlugin.kt:836-845` hardcodes `permanent: true` on **every** error,
including `error_no_match` and `error_speech_timeout` — the two most common and
most benign. The app's guard read:

```dart
final quiet = message.contains('no match') || ... || error.permanent;
if (_turnActive && quiet && !error.permanent) { _restartSession(); return; }
```

`!error.permanent` is never true, so the recovery branch was dead code. Worse,
Android sends `error_no_match` (underscores) while the check looks for
`'no match'` (a space), so even the string test never matched. A child pausing
to think produced a no-match that **ended the whole turn and sent half a
question**. This is the largest single cause of symptom 3, and it had been
shipping.

### 3. "Listening" did not mean the microphone was on

`SpeechToTextPlugin.kt:311-318` calls `notifyListening(isRecording = true)` and
`result.success(true)` on the calling thread — *before* the `handler.post` that
runs `speechRecognizer.startListening()`, and long before the recognition
service opens `AudioRecord`. `onReadyForSpeech`, the signal Android provides for
exactly this, was overridden with an empty body (`:843`).

Add the blind `Future.delayed(1200ms)` at `companion_screen.dart:936` and the
child — who has been waiting for Pollie to stop — answers straight into a hole.
This is symptoms 1 and 2, and it explains 4: a 300 ms word fits entirely inside
the dead window. It does not affect the *first* turn because the child's own
reaction time covers the warm-up; it starts biting once the mic re-arms
automatically.

### 4. `minimumLength: 3s`

Forced every session to run at least three seconds, so a one-word answer waited
on a timer with nothing to wait for.

### 5. Two `FlutterTts` instances

`flutter_tts` speaks over a `static const MethodChannel`, and every
`FlutterTts()` constructor re-points that channel's handler at itself. The app
built two — one in `Narrator`, one in Pollie's screen — so whichever lost the
race stopped receiving `speak.onComplete`. For Pollie that means `_pending`
never reaches zero and **the microphone never re-opens**. Not yet reported, but
it presents as "sometimes Pollie just stops listening", which is precisely the
kind of thing that never reproduces on demand.

## What replaced it

### The app owns endpointing

`lib/services/vad_gate.dart` classifies the sound-level stream — raw `rmsdB`,
which the screen previously destroyed with `clamp(0, 1)` for a UI pulse — into
voice and silence:

- floor seeded from the **median** of the first 400 ms (a mean would let one
  door slam mute the child for the whole turn), then tracked by an EMA **on
  silent frames only**, so sustained speech cannot drag the floor up under
  itself;
- +3 dB onset, +1.5 dB release. The hysteresis matters: a single threshold
  chatters on every syllable boundary and each flicker would reset the clock;
- two-frame onset debounce, which rejects a tap or a door but no pair of
  syllables.

Thresholds are **relative to a measured floor, never absolute** — what counts as
quiet depends on the room, the phone, and how far away the child is holding it.

Silence is **accumulated by a `Timer.periodic(100ms)` gated on the mic actually
recording**, not computed from `DateTime.now()`. Three reasons, the third
decisive: a restart gap must contribute nothing; some OEMs stop reporting levels
in true silence; and `Timer` is controllable inside a widget test while
`DateTime.now()` is not — without this choice none of the turn machine could be
tested at all.

| Constant | Value | Replaces |
|---|---|---|
| `_endTurnOnSilence` | 2200 ms | `_quietEndsTurn` 4 s + `pauseFor` 3 s |
| `_endTurnAfterFinal` | 900 ms | — (fast path for short answers) |
| `_noVoiceGivesUp` | 8 s | `_silenceGivesUp` 12 s |
| `_noWordsGivesUp` | 12 s | — (a different failure, a different answer) |
| `_readyTimeout` | 1200 ms | — (nothing may hard-depend on `ready`) |
| post-speech delay | **0 ms** | the blind 1200 ms |

2200 ms is the single most important number here. It is now *acoustic* silence
rather than "the transcript stopped moving", so it can be far shorter than the
four seconds it replaces — but it still has to survive a four-year-old thinking
mid-sentence, which reaches about two seconds.

The fast path is its own timer rather than a branch in the tick, because a final
result restarts the session and the mic goes cold for a few hundred milliseconds
— the accumulator is deliberately paused for exactly that window, so it cannot
be the thing that notices. It only arms when the recogniser says *finished* and
the room agrees, and any voice cancels it.

### The plugin tells the truth

Patch 2 in `packages/PATCH.md`: `onReadyForSpeech` forwarded as a status string,
and a new `completeSilence` option that sets Android's long silence timer
**without** arming the Dart-side one. The load-bearing line is an early `return`
in `_onNotifyStatus` — falling through to `_listening = status ==
listeningStatus` would set `isListening` false while the mic is hot, silently
killing the sound levels the whole design now rests on.

Both native timers (4 s and 6 s) now sit well beyond the app's 2.2 s, so the app
always decides first and the recogniser's guesses are a safety net rather than a
competitor.

### Hold to talk

Press and hold, and the finger owns the turn: silence detection is not allowed
to end it. This is the one path that cannot misjudge, and it is what the child
falls back on in a noisy room.

`Listener` with `onPointerDown`/`Up`/`Cancel`, not `GestureDetector`:
`onLongPressStart` only fires after Flutter's 500 ms threshold, which would lose
the first half-second of a held turn, and a four-year-old's "tap" is slow enough
to trip it. Finger-down starts the mic — which also makes a plain tap ~100 ms
faster — and only the release differs. Under 250 ms it was a tap and the gate
takes over; over 250 ms the turn closes after a 350 ms tail, because Android's
audio pipeline lags the finger and closing on the release itself clips the last
syllable. Pointer-cancel is treated as a release, so a finger dragged off cannot
strand a hot microphone.

### One TTS engine

`lib/services/tts_service.dart` owns the app's only `FlutterTts` and hands out
sessions; the newest owner wins, and a late callback from a released session is
dropped rather than decrementing someone else's counter. Queue mode is applied
per acquisition, since the Narrator wants *replace* and Pollie wants *queue* on
the same global engine. A ten-second watchdog makes the symptom impossible even
if the cause returns some other way, and a source-scanning test fails the build
if a second `FlutterTts` is ever constructed.

### What the child sees

Amber while the mic is warming, red when it is genuinely recording, with one
haptic tick at the transition. That instant is the honest answer to "the child
talks into the dead gap": there is now a visible moment when the microphone goes
live, and it is truthful rather than optimistic. No earcon — it would either
land inside the recording or have to play before the mic was hot, which is the
bug being fixed.

The `AnimatedScale` that wrapped the 🎤 emoji and scaled it with the sound level
is deleted. That is golden rule 4 — scaling an emoji re-rasterises the glyph
every frame and eventually stops emoji painting app-wide — and it was shipping.
The level now drives a bar's **width**, which is layout, not a transform.

## Testing

53 new tests. The seams that made them possible did not exist before:
`SpeechSink` (because `SpeechToText()` is a process-wide singleton whose state
leaks between tests), `TtsSink`, and a pure `VadGate`.

Every fix above was confirmed to **fail** the suite when reverted. Two early
attempts did not: the production listen options were only exercised through a
fake sink, and the restart-gap guard turned out to be defence-in-depth rather
than load-bearing — the 1200 ms ready-timeout already bounds the blind window
below the 2200 ms endpoint. The first got a real test against the production
sink; the second's test was rewritten to claim only what it proves.

Scenarios worth naming, each pinning a reported symptom:

- speech / 2 s pause / speech ⇒ **one** turn carrying both halves
- twenty identical partials with no voice ⇒ still ends on silence, not on text
- `error_no_match` mid-turn ⇒ the turn survives
- two finals "do you" / "do you know" ⇒ `"do you know"`, not the stutter
- `ready` never arrives ⇒ proceeds at 1200 ms, so an unpatched platform works
- TTS completion never fires ⇒ the watchdog opens the mic anyway
- a held mic ignores four seconds of silence; releasing keeps the last word
- no `AnimatedScale`/`Transform` above the 🎤

## Still to do

Device verification on the Xiaomi 15, with speech played from the Mac's
speakers: `say "in minecraft how do you [[slnc 2000]] create a tnt"` reproduces
the exact reported bug as a deterministic two-second acoustic gap, and
`adb shell input swipe X Y X Y 3000` (identical start and end) is a three-second
press-and-hold. Six consecutive turns per run, because the symptom is explicitly
"not the first turn".
