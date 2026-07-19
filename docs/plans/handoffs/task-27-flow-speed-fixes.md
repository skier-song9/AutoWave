# Codex Handoff — Task 27: Flow simplification + speed button (3rd report) + constant fall speed

Read `AGENTS.md` first. Same invariants. Orchestrator runs build+tests only —
self-check your diff. Owner device-test round 4.

## 1. Remove the pre-READY difficulty picker page

The READY sheet now contains a difficulty selector, so the old difficulty
picker (shown when tapping a converted track in the library/music-select
list) is redundant. Change the flow: tapping a converted track opens the
READY sheet DIRECTLY (with its difficulty segmented control defaulting to the
last-played or normal). Unconverted tracks still route to Analysis. Delete the
now-dead picker UI and its state; keep navigation to gameplay working from
the READY sheet's 시작.

## 2. Speed button — THIRD report, still does nothing

Two prior "fixes" claimed success; the owner still sees no effect. Stop
assuming — instrument and split the failure:
a. Read the CURRENT wiring completely: where the button lives (SwiftUI layer
   over SpriteView), what action it calls, where the multiplier is stored,
   and how GameScene consumes it each frame.
b. Likely bugs to check hard: (i) the SwiftUI overlay stacked UNDER the
   SpriteView or with allowsHitTesting lost, so taps never arrive — verify
   ZStack order and add `.zIndex`; SpriteView must not swallow touches for
   the button's frame; (ii) the scene reads a multiplier captured at init
   (constant) instead of polling the live thread-safe value — the scene must
   poll a lock-guarded/atomic value every frame; (iii) two different
   multiplier sources (ProfileEntity vs view model vs READY sheet) that
   don't agree — unify to ONE source of truth read by all.
c. Make the button's visual state unmissable: label always shows current
   value ("x1.0" etc.) and flashes on change — so if it still fails the owner
   can report whether the LABEL changes (consumption bug) or not (touch bug).
d. Tests: unit test the cycle action mutates the shared source of truth; test
   that GameScene's effective per-frame scroll speed (expose for testing)
   reflects a changed multiplier WITHOUT recreating the scene.

## 3. Constant fall speed in the perspective field

The perspective implementation eases the time→y mapping (t^1.15-style), so
notes move fast then slow. Owner wants CONSTANT speed: time→y strictly
linear (y advances at scrollSpeed × multiplier px/s, exactly as pre-
perspective), with perspective applied ONLY to x-convergence and node scale.
Remove the easing exponent; keep the trapezoid geometry. Update the
projection unit tests: equal time deltas ⇒ equal y deltas at every t.

## Verification

`xcodegen generate` if needed. Typecheck; one xcodebuild attempt max. All
tests green (projection tests updated per above). Korean UI strings.
