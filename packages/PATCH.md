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

## Upgrading

The patch is about fifteen lines in three files. To move to a newer upstream:

1. Copy the new version over the top, minus `example/`, `test/`, `.dart_tool/`.
2. Search the old copy for `TINY TAPSTERS PATCH` and re-apply each block.
3. Check `setupRecognizerIntent` still guards on the `previous*` values.
4. Test on a real phone: nothing here can be verified from a unit test.

Check first whether upstream has added these options — if so, drop the fork and
go back to pub.

## Analysis

`analysis_options.yaml` excludes `packages/**`. This is upstream code; we
maintain a patch, not its style.
