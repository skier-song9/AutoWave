# Codex Handoff — Task 8: Drag ribbons (hold + lateral movement + break rule)

Read `AGENTS.md` and the Task 8 section of `docs/plans/2026-07-17-autowave-mvp.md`
first. Extends Task 7's engine and scene — read the merged
`AutoWave/Features/Gameplay/` sources before coding; extend, don't rewrite.
Write engine tests FIRST.

## Files

- Modify: `AutoWave/Features/Gameplay/JudgmentEngine.swift`
- Modify: `AutoWave/Features/Gameplay/GameScene.swift`
- Modify/extend: `AutoWaveTests/JudgmentEngineTests.swift`

## Engine additions (exact semantics — this is the spec's core rule)

```swift
enum DragTickResult: Equatable { case scored(points: Int, combo: Int), broken, finished, inactive }
```

- Drag note lifecycle: `pending` → `active` (head hit within GOOD window,
  judged like a tap for the head: perfect/great/good points + combo) →
  `finished` (held to the end) or `broken`.
- While `active`, the caller invokes
  `dragTick(noteID: UUID, touchLane: Double?, at time: TimeInterval)` every
  0.1 s of playback time:
  - `touchLane` = current finger lane position (Double), `nil` = finger lifted.
  - Spine lane at `time` = interpolation of `Note.lane` + `lanePath`
    keyframes (linear between keyframes; constant before first/after last).
  - Within tolerance `abs(touchLane - spineLane) <= 0.6` ⇒ `scored(points: 10 × combo multiplier as in tap scoring, combo: combo+1)` — each tick
    increments combo by 1 and adds `floor(10 * (1 + min(combo_before, 100)/100))` points.
  - Finger lifted or out of tolerance before the drag's end time ⇒ `broken`:
    combo resets to 0, and **every subsequent tick for that noteID returns
    `inactive` with zero points — permanently**. The head already scored stays
    scored; no retroactive removal.
  - Tick at/after `time >= note.time + note.duration` on an unbroken active
    drag ⇒ `finished` (no extra points beyond the tick schedule).
- Missing the head entirely (never activated within GOOD window) ⇒ the whole
  drag is one MISS at head timeout (existing miss path), remainder inactive.
- Judgment counts: broken drag counts one MISS at break time; finished drag
  counts nothing extra beyond its head judgment (head already counted).

## Scene additions

- **Ribbon rendering ("물결" wave ribbon)**: translucent band along the drag's
  spine — build the spine path from `lane`/`lanePath` (lane→x mapping, time→y
  mapping consistent with scroll speed), stroke with an `SKShapeNode` spline
  (width ~ lane width × 0.55, alpha ~0.45) plus a brighter core line; subtle
  sine undulation via path offset so it reads as water, not a straight bar.
- Crest glow: an SKShapeNode circle riding the spine at the current playback
  time position while the drag is active and the finger is on it.
- Break state: recolor remaining ribbon segment grey (desaturate, alpha 0.25),
  kill the crest glow. Completed segment keeps its color.
- Touch tracking: `touchesMoved`/`touchesEnded` update the engine's
  `touchLane` for active drags; scene drives `dragTick` on its 0.1 s schedule
  from playback time (accumulate in `update(_:)`, no Timer).

## Tests (extend JudgmentEngineTests — write first)

1. Head hit + full hold: activate on time, ticks every 0.1 s in tolerance to
   the end ⇒ all `scored`, then `finished`; combo == head + tick count.
2. Tolerance edge: tick at `abs(delta) == 0.6` scores; `0.61` breaks.
3. Break permanence: after one out-of-tolerance tick ⇒ `broken` once, then
   `inactive` for all later ticks even if the finger returns to the spine;
   score unchanged after break; combo reset to 0 at break.
4. Finger lift (`touchLane == nil`) mid-drag ⇒ same break semantics.
5. Moving drag interpolation: `lanePath` keyframes (e.g. lane 1 → 2.5 over
   1 s), tick halfway with touchLane 1.75 ⇒ scored (spine interpolated).
6. Broken drag adds exactly one miss to judgment counts.

## Verification & constraints

- `xcodegen generate`; typecheck; orchestrator runs simulator gate + manual
  smoke run with a drag-heavy hell map.
- No third-party deps. No git. No allocation in per-frame paths.
