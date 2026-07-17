# Codex Handoff — Task 16: Gameplay scene redesign (N lanes, note feel, HP/combo HUD)

Read `AGENTS.md` first. Depends on Task 14 (scoring/life/`isGameOver`) and Task
15 (variable `laneCount` on Beatmap/DifficultyProfile). CRITICAL invariants
from prior crash fixes — do NOT regress: GameScene callbacks (didMove/update/
touches and everything they call) run OFF the main actor on device; use the
existing lock-guarded `PlaybackClock` and nonisolated visualizer pull; hop to
`@MainActor` via `Task { @MainActor … }` only for haptics / view-model /
completion; no allocation in per-frame paths (pool nodes); AVFoundation
closures `@Sendable`. Reference look: attached #6/#7 (retro neon lane rhythm
game) — REINTERPRET, do not clone pixel art.

## 1. N-lane rendering

- Render `beatmap.laneCount` lanes (4–7) spread across the landscape width,
  centered, with clear vertical separator lines and per-lane alternating fills
  (Task 11 theme colors). Lane width scales to fit the count.
- Map `Note.lane` (Double, 0..<laneCount) to x-position by lane center.
- Touch → lane: map x back to the nearest lane index across `laneCount`.
- Update spawn/scroll and receptor slots to the actual lane count.

## 2. Note feel changes (owner)

- **Remove the approach/contracting timing-guide effect entirely** — notes just
  fall as clean rounded rectangles (corner radius ~8, per-theme fill+stroke).
  No shrinking ring.
- **Add a small ON-HIT effect** when the player taps a note: a brief pop/flash
  + few particles at the receptor in `judgmentAccent`, scaled subtly by
  judgment (perfect brightest). Pool these effect nodes.
- Notes travel from the very top; with the thinner hit line from Task 13 the
  travel time is longer. Keep scroll speed from `DifficultyProfile`.
- Drag notes: straight body with tap-note-shaped head/tail caps (Task 11);
  keep break→grey. Ensure they render correctly across the new lane counts and
  moving drags use straight polyline segments.

## 3. HUD (reference #6/#7)

Landscape HUD, non-overlapping with lanes (use side gutters):
- **Combo**: large combo count + latest judgment label (PERFECT/GREAT/GOOD/
  BAD/MISS) near center-top, briefly animated on change. Read from engine.
- **Score**: running total score, prominent (bottom gutter, like the #6/#7
  odometer — a simple styled number is fine).
- **Life gauge**: a vertical bar (right gutter) showing `engine.life`/100,
  color shifting green→amber→red as it drops. Update each frame from the
  engine (nonisolated read; `life` is a plain Int on the engine — reading it
  from the scene queue is fine since the engine is only mutated on the scene
  callback queue).
- Keep pause button (top gutter) and existing pause overlay.

## 4. Game-over on life 0 (owner: 즉시 Fail)

- Each frame after advancing judgments, check `engine.isGameOver`. On first
  true: stop scheduling notes, stop playback via the completion path, and route
  to results as a FAILED run. Add a `failed: Bool` (or reason) to
  `GameplaySummary` so the results screen (Task 18) can show a fail state.
  Trigger completion the same way song-end does (the onComplete hop to
  MainActor), passing the failed flag. Show a brief "게임 오버" flash before the
  results transition.

## 5. Verification

- `xcodegen generate` if needed. Typecheck; orchestrator runs the simulator
  gate + a real play smoke test at multiple difficulties (4 and 7 lanes) and
  checks: notes are rounded rects with no approach effect, on-hit pop shows,
  HP/combo/score HUD updates, life-0 ends the run to a failed result.
- All existing tests stay green. The GameplayStartRegressionTests must keep
  passing (extend it if you add new scene inputs) and MUST still drive
  `scene.update` from a background queue without dispatch assertions.
