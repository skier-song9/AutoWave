# Codex Handoff — Task 7: Gameplay scene (tap notes, scoring, results)

Read `AGENTS.md`, the Task 7 section of `docs/plans/2026-07-17-autowave-mvp.md`,
and the "Visual identity" section of that plan first. Depends on Tasks 2–6.
Check merged signatures in `AutoWave/Core/` before coding. Write
`JudgmentEngine` tests FIRST; the scene itself is verified by build + manual run.

## Files

- Create: `AutoWave/Features/Gameplay/GameScene.swift`
- Create: `AutoWave/Features/Gameplay/JudgmentEngine.swift`
- Create: `AutoWave/Features/Gameplay/GameplayViewModel.swift`
- Create: `AutoWave/Features/Gameplay/ResultsView.swift`
- Rewrite: `AutoWave/Features/Gameplay/GameplayContainerView.swift`
- Test: `AutoWaveTests/JudgmentEngineTests.swift`

## JudgmentEngine (pure Swift, fully unit-tested)

```swift
enum Judgment: Equatable { case perfect, great, good, miss }
struct JudgmentResult: Equatable { var judgment: Judgment; var pointsAwarded: Int; var combo: Int; var score: Int }
```

- Windows around each note's time: PERFECT ±0.050 s → 100 base points,
  GREAT ±0.100 s → 70, GOOD ±0.150 s → 40, outside → not hittable.
- A tap consumes the nearest unconsumed tap note in the touched lane within
  ±0.150 s; if none, the tap is ignored (no penalty).
- A note whose time passes beyond +0.150 s unconsumed becomes a MISS.
- Combo: +1 on perfect/great/good; reset to 0 on miss.
- Score: `score += basePoints * (1 + min(combo_before_this_hit, 100)/100)`
  using integer math (multiplier as Double, result truncated).
- Engine is deterministic and time-driven: caller feeds
  `tap(lane: Int, at: TimeInterval)` and `advance(to: TimeInterval)` (which
  emits misses); engine holds the beatmap's tap notes sorted by time.
- Track judgment counts (perfect/great/good/miss) and maxCombo for results.
- Design the API so drag support can be added in Task 8 without breaking
  callers (e.g. engine takes all notes but currently judges `kind == .tap`;
  ignore drags for now).

## GameScene (SpriteKit, landscape)

- 4 vertical lanes across the width; subtle wave-line lane separators; hit
  line ~15% from the bottom.
- **Note visual ("물방울" droplet)**: filled core dot + two concentric rings;
  the outer ring contracts toward the core as the note approaches, coinciding
  exactly at hit time (ring radius linear in time-to-hit). Build with
  SKShapeNode/SKNode composition; pool and reuse nodes (no per-note alloc at
  60 fps for hell density).
- Notes scroll top→bottom at `DifficultyProfile.profile(for:).scrollSpeed`
  points/sec; spawn when their y-position would enter the screen.
- **Timing source**: audio playback position — `AVAudioPlayerNode` +
  `playerNode.lastRenderTime`/`playerTime(forNodeTime:)` — never wall clock.
  Scene update loop converts playback time to note positions and calls
  `engine.advance(to:)`.
- Touch handling: `touchesBegan` maps x → lane, calls `engine.tap(lane:at:)`
  with current playback time; show judgment label (PERFECT/GREAT/GOOD/MISS +
  combo count) center-screen; ripple splash SKEmitter/scale-fade effect on hit.
- Background: solid dark color tinted by `Beatmap.palette` for now (Task 9
  adds the reactive visualizer).
- Song end (playback finished or last note + 2 s) → completion callback.

## GameplayViewModel + views

- `GameplayViewModel`: loads `Beatmap` from the chosen `BeatmapEntity`
  (JSON-decode), owns AVAudioEngine/PlayerNode setup with the track's
  `audioURL`, exposes engine results; on completion saves a `ScoreRecord`
  (score, maxCombo, difficulty, playedAt) into the ModelContext.
- `GameplayContainerView(track:difficulty:)`: hosts `SpriteView(scene:)`,
  full-screen, ignores safe area, locks to landscape while presented
  (AppDelegate/orientation-lock helper or `.persistentSystemOverlays(.hidden)`
  + supported-orientations plumbing — choose the simplest reliable approach
  for iOS 17), navigates to `ResultsView` on completion.
- `ResultsView`: score, max combo, judgment counts, buttons "다시하기"
  (restart same beatmap) and "라이브러리" (pop to root). Korean copy.

## Tests (JudgmentEngineTests — write first)

1. Window edges: tap at exactly ±0.050/±0.100/±0.150 relative to a note ⇒
   perfect/great/good respectively (boundary inclusive); at ±0.151 ⇒ ignored.
2. Miss emission: `advance(to:)` past note time +0.150 with no tap ⇒ miss,
   combo resets.
3. Combo/score math: sequence of 3 perfects ⇒ score 100 + 101 + 102 = 303
   (multiplier from combo before hit: 0,1,2 → floor(100*1.00)+floor(100*1.01)+floor(100*1.02)).
4. Nearest-note selection: two taps 0.12 s apart in one lane, tap lands
   between them ⇒ consumes the nearer; second tap consumes the other.
5. Drag notes present in beatmap are ignored by tap judgment (no crash, no
   consumption).

## Verification & constraints

- `xcodegen generate`; typecheck; orchestrator runs simulator test gate and a
  manual smoke run.
- No third-party deps. No git. UI strings Korean. 60 fps mindset: pool nodes,
  no allocation in `update(_:)`.
