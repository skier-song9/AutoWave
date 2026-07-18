# Codex Handoff — Task 20: Drag note overhaul (hold-through judgment, visuals, span rule)

Read `AGENTS.md` first. Same invariants as always (off-main scene callbacks,
no per-frame allocs, @Sendable audio closures). Owner device-test feedback,
reference image #11 (Beat MP3-style: drag segments connect lane-to-lane with
STEPPED right-angle connectors, not diagonals). Fix all items below.

## 1. Drag end must NOT require a re-tap; no end-miss while holding

Owner: "드래그 시작~홀드는 인식되는데 끝 노트에서 miss가 된다. 끝에서 다시
클릭할 필요 없이 드래그 유지 중이면 인식되어야 한다."
Diagnose the end-of-drag path in `JudgmentEngine`/`GameScene`: when a drag is
`.active` and the finger is still within tolerance at `time >= note.time +
duration`, the drag must resolve as SUCCESS (`.finished`) — no miss, no
additional tap. Audit: (a) the tail is probably represented as a separate
pending tap note or the finish path never runs because ticks stop early;
(b) `touchesEnded` after finish must not retro-break; (c) the engine's
`advance` must not emit a miss for a drag that finished successfully. Add
engine tests: hold in tolerance through the full duration ⇒ ticks then
`.finished`, zero misses; finger lift AFTER duration end ⇒ still finished.

## 2. Drag body must disappear through the hit line when being played

Owner: "정상 드래그 중인데 드래그 노트가 hit line에서 없어지지 않는다."
While a drag is active (or finished), the portion of the ribbon that has
passed the hit line must be consumed/hidden progressively — like tap notes
vanish on hit. Implement: clip/trim the ribbon's rendered path at the hit
line while active (head cap disappears on successful begin; body shrinks as
playback progresses; tail cap disappears on finish). A broken drag keeps the
grey remainder falling (current behavior).

## 3. Lane-crossing tolerance too strict

Owner: "여러 lane에 걸칠 때 다른 레인으로 드래그하는 판정이 너무 빡빡하다."
Current tolerance: `abs(touchLane - spineLane) <= 0.6`. Loosen for moving
drags: raise tolerance to 1.0 lane during transition windows (±0.15 s around
each lanePath keyframe) and 0.8 elsewhere; also grade the spine position with
the STEPPED model from item 4 (the spine holds a lane then jumps at the
keyframe, rather than gliding diagonally) so the expected finger position
matches what the player sees. Update engine tests accordingly.

## 4. Stepped (right-angle) drag rendering like reference #11

Replace diagonal polyline rendering between lane keyframes with stepped
connectors: vertical ribbon segment in lane A until the keyframe time, a
HORIZONTAL connector bar at the keyframe's y, then vertical segment in lane B.
(Reference #11: white pipes with right-angle elbows.) Head/tail caps stay
tap-note-shaped. The engine's `lane(at:)` interpolation must match the stepped
geometry: constant lane until keyframe, instant switch at keyframe (with the
transition tolerance from item 3 covering the jump moment).

## 5. Touch/hold effect on drags

Owner: "드래그 노트를 클릭·드래그해도 이펙트가 없음." Add: on successful
drag begin, the same on-hit pop as tap notes at the receptor; while holding,
a glow/pulse at the hit line position of the ribbon (pooled node, driven from
update, no per-frame alloc); on each scored tick a subtle brightness pulse.

## 6. Drag-span tap exclusion is not working in practice (owner items 16/17)

Owner still sees tap notes inside a drag's lane span during its time window.
The generator has `removeDragSpanConflicts` — find why it leaks: likely (a)
span computed from diagonal interpolation while rendering now steps (use the
FULL min…max lane range of the drag inclusive, integer-expanded:
floor(minLane)…ceil(maxLane)), (b) chord-preservation or gap-fill paths
insert taps AFTER the conflict pass, or (c) time window lacks a margin —
extend exclusion window by ±0.15 s beyond [time, time+duration]. Order the
pipeline so NO tap can be added inside a drag span after the exclusion pass.
Strengthen the generator test: for every drag, no tap within its expanded
lane range and padded time window, across all difficulties and many seeds
(loop 10 seeds).

## Verification

`xcodegen generate` if needed. Orchestrator runs build+tests only (owner
verifies by playing — no code review), so re-read your own diff carefully.
All existing tests + GameplayStartRegressionTests must stay green; add the
new engine/generator tests above.
