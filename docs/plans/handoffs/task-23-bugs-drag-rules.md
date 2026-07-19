# Codex Handoff — Task 23: Speed button, background-pause, drag rule fixes

Read `AGENTS.md` first. Same invariants (off-main scene callbacks, no per-frame
allocs, @Sendable audio closures, deterministic BeatmapKit). Owner device-test
round 3. The orchestrator does NOT code-review — self-check your diff; all
tests must stay green.

## 1. Speed button STILL does not work (2nd report)

Owner: tapping the 배속 button does nothing. Trace the full path end-to-end
and fix wherever it breaks:
- Is the SwiftUI button actually receiving taps (z-order over SpriteView,
  hit-testing, allowsHitTesting)?
- Does the tap cycle the value x0.5→x0.75→x1.0→x1.5→x0.5 in the view model?
- Does the label update?
- Does the SCENE actually consume the new multiplier (scrollSpeed ×
  multiplier) on the next frame — check how the scene reads the value (it must
  be a thread-safe read the scene polls, not a one-shot captured at init)?
- Is it persisted to ProfileEntity and loaded on next gameplay?
Add a unit test for the cycle function AND a test that GameScene's effective
scroll speed changes after the multiplier updates (expose the effective speed
for testing). Manually reason through the touch path since the owner cannot
debug for you.

## 2. Backgrounding must PAUSE, never END the game (2nd report)

Owner: accidental bottom-edge home swipe backgrounds the app and the game
ENDS instead of pausing. ROOT CAUSE HYPOTHESIS (verify): `pause()` calls
`playerNode.stop()`, and AVAudioPlayerNode fires its scheduleFile/
scheduleSegment COMPLETION HANDLER on stop() — which does
`clock.setFinished(true)` — so the scene's update loop sees playbackFinished
and completes the run. Fix properly:
- Distinguish natural end from manual stop: e.g. use
  `scheduleFile(_:at:completionCallbackType: .dataPlayedBack)` and/or set a
  `suppressCompletion` flag on the clock before calling stop() in
  pause()/resume re-scheduling paths, cleared after; only a natural
  completion sets finished.
- The scene must not complete while `isPaused` regardless of the finished
  flag.
- Also ensure scenePhase `.background`/`.inactive` triggers pause() (owner
  says it currently doesn't reliably) and that returning shows the pause
  overlay with countdown resume.
- Additionally reduce accidental home-swipe: enable the deferred system
  gesture edge (`preferredScreenEdgesDeferringSystemGestures = [.bottom]`)
  for the gameplay screen so the first swipe only shows the indicator.
Add a regression test at the engine/view-model level: simulate pause() → the
completion handler firing → resume() → game must still be running (not
completed).

## 3. Drag notes: one lane per step

Owner: drags currently jump too many lanes at once. In BeatmapGenerator,
lanePath keyframes must move at most ±1 lane per keyframe step (a drag can
still traverse several lanes total via multiple sequential steps, each ≥ ~0.35 s
apart). Regenerate-affecting change: bump generator version (5→6) so stored
maps auto-regenerate. Update generator tests: every consecutive lanePath pair
differs by exactly ≤1.0 lane; steps spaced ≥0.3 s.

## 4. No tail cap on drag notes

Remove the tail-end tap-note-shaped cap from drag rendering (keep the HEAD
cap). The ribbon simply ends at the tail time (#18 reference: capsule head,
plain pipe end). Adjust any tests referencing tail caps.

## 5. Drag judgment more lenient than taps

- Drag head begin window: accept within the BAD window (±0.150 s) but award
  at minimum GOOD judgment for any successful begin (never bad on a drag
  head), PERFECT/GREAT per normal windows.
- Hold tolerance: raise base lane tolerance 0.8 → 1.1, transition-window
  tolerance 1.0 → 1.5.
- Tick grace: allow up to 0.25 s out-of-tolerance before breaking (grace
  timer, reset when back in tolerance) instead of instant break.
Update engine tests to the new semantics (rewrite tolerance-edge tests
accordingly, keep break-permanence and finish rules).

## Verification

`xcodegen generate` if needed. Typecheck; one xcodebuild attempt max. All
existing tests green (GameplayStartRegressionTests, GameplayStabilityTests
included) plus the new ones above.
