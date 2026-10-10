# Pollie text-input microphone privacy Task 1 implementation plan

**Goal:** Implement the approved text/voice boundary and prepare Tiny Tapsters
`1.25.9+62` for parent-owned review and release.

**Architecture:** Keep the existing listening turn machine, VAD, transcript
banking, shared TTS, and timing values. Lazy speech initialization belongs to an
explicit microphone press. Voice consent plus a generation identifies permitted
starts; text focus/edit/submission, suggestions, backgrounding, reset, and disposal
invalidate it. Deferred starts recheck both consent and generation.

**Tech stack:** Existing Flutter `SpeechSink`, `PollieService`, `TtsService`,
`FocusNode`, `TextField.onChanged`, and widget tests.

**Requirements:** `.superpowers/sdd/2026-10-10-pollie-text-mic-privacy/task-1-brief.md`,
the approved parent plan, `2026-08-11-pollie-microphone-design.md`, and
`docs/pollie-architecture-and-costs.md`.

## Constraints and decisions

- Work on `codex/pollie-text-mic-privacy`, base
  `57537d6ce6586bb40b0c0e672c3ce44b8645ce22` in the supplied clone.
- No subagents, push, tag, deployment, or device actions. Parent owns release.
- Preserve `graphify-out/` and the existing parent plan; include both this newly
  written Task 1 plan and the approved parent plan in the implementation commit.
- No UI redesign or dependency/native changes. Text remains editable during
  recognition; disable only during an outstanding network request.
- `onChanged` observes user edits, not controller clearing. Focus listener and
  tap handling cover entering a still-empty or already-focused text field.
- A quick press released during permission initialization may start a tap turn;
  a released deliberate hold must never become a stale held turn. Typing,
  backgrounding, reset, and disposal always invalidate the pending start.
- Keep the exact hold/VAD/watchdog timers. A stale callback must not inherit a
  later explicit voice session's consent.

## Review focus

- Pending initialization after quick release, held release, or pointer cancel.
- Focus/edit while recognition, TTS, or restart delays are active.
- Old voice restart after text mode and then a new explicit voice session.
- Empty/brief-quota/network failures and missing TTS completion.
- Backgrounding during initialization, speaking, or a scheduled restart;
  resuming alone does not enable voice.

## Execution

- [x] Add initialization counter/completer and error fixture to existing fakes.
  Test real screen open/typed/suggestion paths, focus/edit cancellation, delayed
  initialization, denial, lifecycle, error retries, and voice continuation.
- [x] Run `flutter test --no-pub test/pollie_turn_test.dart --reporter expanded`
  before production edits; retain failing assertions and actual output.
- [x] Remove eager initialization. Track consent/generation and pointer state;
  guard start/restart/retry paths before and after awaited work. Invalidate voice
  intent on text and background. Use focus/edit callbacks without observing
  programmatic controller changes.
- [x] Run focused tests and affected widget tests; preserve existing hold,
  acoustic endpointing, readiness, retry limits, and watchdog coverage.
- [x] Set version `1.25.9+62`; synchronize README, CHANGELOG, AGENTS, CLAUDE,
  architecture docs, and add privacy supersession notes to historical specs.
  Inventory intentionally unchanged Markdown in the report.
- [x] Run `dart format lib/ test/`, documentation test, then `./tool/check.sh`.
  Self-review the full diff and retain the complete gate output.
- [x] Write `.superpowers/sdd/2026-10-10-pollie-text-mic-privacy/task-1-report.md`
  with `apply_patch`. Stage exact paths and commit only after the gate passes:
  `fix(pollie): keep text conversations microphone-free`.
