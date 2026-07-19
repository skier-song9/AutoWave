# Codex Handoff — Task 24: Perspective trapezoid playfield + HUD rework

Read `AGENTS.md` first. Same invariants (off-main scene callbacks, no
per-frame allocation — pool everything, precompute projection tables). Owner
references #17/#18 (BEAT MP3): the playfield is a TRAPEZOID — narrow at the
top, widening toward the bottom hit line, like a road receding into the
distance. Keep every existing element: touch line/receptors, lanes, speed
button, pause, HP bar, score. Orchestrator does NOT code-review — self-check.

## 1. Perspective projection (GameScene)

- Define a projection: at normalized progress `t` (0 = spawn at top, 1 = hit
  line), the playfield half-width interpolates from `topHalfWidth` (~22% of
  bottom width) to `bottomHalfWidth` (lane area = 70% of scene width at the
  hit line). Lane k's x at progress t: `centerX + (k + 0.5 - laneCount/2) *
  laneWidthAt(t)` where `laneWidthAt(t) = bottomLaneWidth * (topScale + (1 -
  topScale) * t)` with `topScale ≈ 0.22`.
- Vertical mapping: keep time→progress linear (`t = 1 - timeToHit *
  scrollSpeed / travelHeight` equivalent to current), y from t as now (top →
  hit line). Optionally ease y slightly (t^1.15) so notes visually accelerate
  toward the player like the reference — keep judgment purely time-based
  (unchanged engine).
- Note nodes scale with perspective: `setScale(topScale + (1-topScale)*t)`;
  width already follows laneWidthAt(t) via scale (build note geometry at
  bottom-size and scale down).
- Lane separator lines become converging straight lines from top center
  region to the bottom (5–8 lines depending on laneCount) — redraw once per
  layout, not per frame.
- Drag ribbons: spine points use the same projection (x depends on BOTH lane
  and t now). Stepped connectors follow the projected geometry (horizontal
  connector at the keyframe's y, spanning the two lanes' projected x at that
  y). Rebuild ribbon paths only when layout changes or per-frame via
  preallocated CGMutablePath reuse — measure that update() stays
  allocation-light (path rebuild for ACTIVE ribbons only is acceptable).
- Receptors/touch line: unchanged position (bottom, 70% width) — touch
  mapping still uses bottom lane geometry (fingers interact at the hit line;
  no perspective needed for input).
- Background/ripples/scanline continue to work behind the trapezoid.

## 2. HUD rework (owner + #18)

- Judgments in ENGLISH, center-top: "PERFECT" / "GREAT" / "GOOD" / "BAD" /
  "MISS" with the existing per-judgment colors, retro bold font.
- Under it, the CONSECUTIVE HIT COUNT (current combo number) — count only,
  large digits (reference #18: "GREAT 48"). Remove the Korean judgment text
  and the "콤보" caption.
- Total score: RIGHT side panel (keep the odometer style), like the
  reference's right circle. HP gauge stays left. Pause + speed buttons keep
  their current SwiftUI-layer placement (don't regress Task 23's fixes if
  merged before this).

## Verification

`xcodegen generate` if needed. Typecheck; one xcodebuild attempt max. All
tests green — GameplayStartRegressionTests drives update from a background
queue and must stay green; extend it if projection helpers need coverage
(pure projection math deserves a small unit test: monotonic width growth,
lane x symmetry, t=1 matches bottom geometry).
