# Codex Handoff — Task 19: Stability + input correctness (crash, game-over, multitouch, early end)

Read `AGENTS.md` first. Preserve crash-fix invariants: GameScene callbacks run
OFF the main actor (SpriteKit render queue on device); PlaybackClock/lock
patterns; `@Sendable` AVFoundation closures; `Task { @MainActor }` hops for
haptics/view-model/completion; no per-frame allocation. All tests must pass.

These are confirmed defects from review + owner device testing. Fix all.

## 1. Life-gauge CGPath crash (crashes every run that gets low life)

`GameScene.updateHUD()` (~line 1327) rebuilds
`CGPath(roundedRect:..., cornerWidth: 8, cornerHeight: 8)` with height
`gaugeHeight * fraction`. When life is low the height drops below 2×corner
radius → CoreGraphics assertion → app aborts (owner-reported "게임이 강제
종료"). Fix: clamp corner radius to `min(8, height/2, width/2)` (or skip path
rebuild and use a scaled fill node); also short-circuit when `life <= 0`
BEFORE building the path. Additionally cache the path and rebuild only when
the integer life value changed (currently rebuilt every frame — waste).

## 2. Life gauge must start visually FULL (owner item 4)

At game start the gauge appears ~50% filled. Audit the fill-height math and
anchor (likely y-anchor/rect origin bug: fill anchored center instead of
bottom, or fraction applied to wrong bound). Life starts at 100 ⇒ gauge must
render 100% at first frame.

## 3. Post-game-over input still scores

`touchesBegan`/`touchesMoved`/drag handlers keep calling
`judgmentEngine.tap/beginDrag/dragTick` after `isGameOverPending`. Guard all
touch handlers (and drag tick scheduling) once game over is pending/completed
so a dead run accepts no input and the saved ScoreRecord contains no
posthumous points.

## 4. `.failed` state soft-lock (no exit)

`GameplayContainerView` hides the back button and disables the pop gesture for
the whole gameplay screen; the `.failed(message:)` state renders text with NO
exit control. Add a "라이브러리로" button to the failed state that dismisses,
and ensure the pop-gesture blocker is released on that path.

## 5. Multitouch is dead — simultaneous notes are unplayable

The SwiftUI `SpriteView` never enables multitouch (UIKit default off) and
`touchesBegan` uses `touches.first` only. Since the generator now emits
2–3 concurrent notes and taps-during-drag, this makes chords guaranteed
misses. Fix:
- Enable multitouch on the underlying view (`view.isMultipleTouchEnabled =
  true` in `didMove(to:)`).
- Process EVERY touch in `touchesBegan`/`Moved`/`Ended`/`Cancelled` (loop over
  `touches`), and track the drag-holding touch by identity (ObjectIdentifier)
  so a second finger tapping other lanes doesn't disturb an active drag hold,
  and lifting the non-drag finger doesn't break the drag.

## 6. Song must play to the END (owner item 27: "첫 N초만 변환하고 게임 종료")

Two suspects — fix both sides:
a. GameScene completion fires at `lastNoteTime + 2` (or when playbackFinished)
   — if the beatmap's notes only cover part of the song, the game ends early.
   Completion must wait for AUDIO end (playbackFinished from PlaybackClock),
   not last-note+2s. Keep a fallback: if audio end never fires, complete at
   `max(audioDuration, lastNoteTime) + 2`.
b. Verify the analysis/generation pipeline covers the full file: check
   `AudioDecoder` for any frame cap/early-exit and `AnalysisViewModel`/
   `BeatmapKit.analyze` progress path for truncation (e.g. buffer count
   miscalc stopping after N seconds). Write a regression test: synthesize a
   120 s WAV with clicks throughout; assert onsets exist in the LAST 10 s and
   generated hell beatmap has notes past 100 s.

## 7. HUD gutter touches steal edge-lane notes

`laneCoordinate(for:)` clamps any x into the lane area, so touches on the
score/life gutters register as edge-lane taps. Ignore touches whose x falls
outside `laneAreaRect` (with a small tolerance of ~half a lane width) instead
of clamping.

## 8. Judgment label lingers forever

`latestJudgmentLabel` gets `alpha = 1` on every judgment and never fades. Add
a fade-out (e.g. after 0.6 s of no new judgment, fade over 0.2 s) driven from
the update loop (no SKAction allocation per hit — track a timestamp).

## Verification

`xcodegen generate` if needed; run the full test suite if your sandbox allows,
else typecheck. The orchestrator runs build+tests only (no code review — the
owner tests on device), so BE THOROUGH: re-read your diff yourself before
finishing, and keep GameplayStartRegressionTests (background-queue drive)
green. Extend it to cover the life-0 path without crashing.
