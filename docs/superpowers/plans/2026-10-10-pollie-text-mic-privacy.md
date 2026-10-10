# Pollie text-input microphone privacy implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan. Steps use checkbox syntax for tracking.

**Goal:** Keep Pollie's microphone off for typed questions, including delayed callbacks, and publish Tiny Tapsters v1.25.9+62.

**Architecture:** Track whether the user has explicitly enabled a voice conversation. Initialize speech recognition only from a microphone press. Switching to typing or backgrounding revokes voice mode, ends active recognition, and invalidates delayed restarts without changing acoustic turn detection.

**Tech Stack:** Flutter, existing SpeechSink and TtsService, widget tests, GitHub Actions signed APK release.

**Spec:** The approved behavior in the following section supplements `docs/superpowers/specs/2026-08-11-pollie-microphone-design.md`.

## Approved behavior

Opening Pollie or typing must not request mic permission/start listening. Typing or selecting a suggestion chip cancels active listening and pending automatic restarts. Only an explicit mic button press enables voice conversation. Hands-free continuation remains for voice mode until switching to typing or backgrounding. Release the fix through a new branch, tests, review, develop/main promotion, a new tag, updated docs, and a signed APK in `/Users/lilianyoctoria/Downloads/tiny-tapsters-apk/`.

## Global Constraints

- Version: `1.25.9+62`; tag: `v1.25.9`; package: `com.inkpebble.tiny_tapsters`.
- Preserve the existing acoustic VAD, transcript banking, hold-to-talk behavior and shared TtsService ownership.
- No Gemini backend change, new permission, analytics, secret in source, or device installation/uninstallation.
- Review amendment: permit scoped changes to the existing vendored speech integration and adapter to retain immutable recognizer/task ownership, retire a canceled recognizer before a successor starts, and reject stale events before they mutate Dart wrapper state. Keep supported native targets compatible; no new dependency, voice feature or timer changes.
- Reuse the existing isolated working clone; preserve untracked `graphify-out/`.
- Run `./tool/check.sh` before every commit and retain the actual output.
- Implementer, read-only reviewer and validation tester are separate roles.
- Do not change Kopi Kompas: the two requests for it are diagnosis only.

## Review Focus

- Speech initialization completes after typing or backgrounding: no recognition starts.
- A voice reply schedules a restart, then the user focuses/types: the callback cannot restart recognition.
- TTS completion never arrives: the watchdog frees the turn without enabling the mic for a typed request.
- Recoverable API errors schedule retries: text mode remains mic-off.
- Permission is delayed beyond the mic pointer-up: voice can start without becoming a stuck hold turn.

### Task 1: Fix Pollie consent and ship regression coverage with current documentation

**Files:**
- Modify: `lib/screens/companion_screen.dart`.
- Test: `test/pollie_turn_test.dart`; adjust existing related widget tests only where expectations intentionally change.
- Review amendment files: existing `lib/services/speech_sink.dart`, vendored speech Dart/platform channel/native listener files, behavioral adapter/plugin tests, and `packages/PATCH.md` as required for recognizer/task ownership. No unrelated vendor refresh.
- Modify: `pubspec.yaml`, `pubspec.lock` if regenerated, `README.md`, `CHANGELOG.md`, `AGENTS.md`, `CLAUDE.md`, `docs/pollie-architecture-and-costs.md`, and current Pollie design documentation where the old startup/listening description conflicts with this fix.

**Interfaces:**
- Consumes: injected `SpeechSink`, `PollieService`, and `TtsService`; existing `_sendTyped`, `_onMicDown`, `_onMicUp`, `_startListening`, `_finishSpeakingIfDone`.
- Produces: text-only conversation never initializes/listens to speech; explicit voice conversation retains bounded automatic continuation.

- [ ] **Step 1: Write and run failing behavioral tests against the existing screen.** Add initialization tracking and a controllable initialization future to FakeSpeech. Exercise the actual screen, not a detached policy helper. For example:

```dart
testWidgets('opening and typing never initialize the microphone', (tester) async {
  await openPollie(tester);
  expect(speech.initializeCalls, 0);
  await tester.enterText(find.byType(TextField), 'Tell me about cats');
  await tester.testTextInput.receiveAction(TextInputAction.send);
  await tester.pump();
  // Complete the fake TTS reply and advance beyond every relisten delay.
  await tester.pump(const Duration(seconds: 12));
  expect(speech.initializeCalls, 0);
  expect(speech.listenCalls, 0);
});
```

Use the existing fake TTS completion API after reading its definition. Add tests for typed success, suggestions, errors, watchdog, focus/typing during a voice restart, background, delayed initialization, denied permission, and explicit voice continuation. Record failing commands/output before changing production code.

- [ ] **Step 2: Implement the minimum state/guard changes.** Remove eager `_initSpeechLocale()` from `initState`; lazy-initialize from the explicit mic handler. Gate `_startListening` and all deferred starts by current voice consent and foreground state, including rechecks after asynchronous initialization. A generation token may invalidate a callback from a prior voice session. Text focus/edit/submission and suggestion chips disable voice mode and cancel recognition/restart intent; keep typing usable while recognition is active. Do not restructure the existing turn machine or replace its VAD timers.
- [ ] **Step 3: Verify focused tests are green.** Run `flutter test --no-pub test/pollie_turn_test.dart --reporter expanded` and affected widget tests. Fix regressions, including held/tapped mic behavior, without weakening privacy assertions.
- [ ] **Review amendment:** Distinguish pointer cancel from pointer up at every press duration. Reproduce and isolate late ready/done/error/result events from retired speech sessions through the real adapter boundary. Native origin identities must survive queued delivery and be rejected before wrapper state changes; do not manufacture provenance only in fakes. Preserve all existing VAD, hold and TTS behavior and test same-turn rearming. Compile the amended native Android integration in a release build; report any unverified Apple/device-specific behavior honestly.
- [ ] **Step 4: Update version and relevant current docs.** Set `version: 1.25.9+62`; document the text/voice privacy behavior and permission timing in README, changelog and Pollie operational/design docs. Update AGENTS and CLAUDE version and guidance consistently. Historical release/design records remain historical; add a supersession note rather than rewriting them as newly implemented features. Inventory Markdown and explain any intentionally unchanged files in the report.
- [ ] **Step 5: Run the gate, self-review and commit.** Run `dart format lib/ test/`, then `./tool/check.sh`. Only on success stage exact changed paths and commit `fix(pollie): keep text conversations microphone-free`. Write the actual RED/GREEN/gate output and changed-file inventory to the task report. No push, tag, release, child agents or device actions by implementer.

### Release coordination after Task 1

- [ ] Independent read-only task review of the full commit diff and report; resolve important findings through the implementer, then scoped re-review.
- [ ] Independent tester runs the full gate and a release build; report actual output and any device-only limitations.
- [ ] Final whole-branch review confirms privacy, release metadata and docs together.
- [ ] Create and attach a PR into develop, wait for passing checks, merge; create and attach promotion PR into main, wait and merge.
- [ ] Create an annotated `v1.25.9` tag on the new main release commit, push, wait for signed GitHub release APK.
- [ ] Download `tiny-tapsters-v1.25.9.apk` into the existing Downloads folder; verify manifest/version/signature/digest, sync original local main without touching its old develop branch.
