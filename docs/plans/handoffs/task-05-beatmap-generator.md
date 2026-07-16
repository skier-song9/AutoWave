# Codex Handoff — Task 5: Beatmap generation (5 difficulties, deterministic, diverse)

Read `AGENTS.md` and the Task 5 section of `docs/plans/2026-07-17-autowave-mvp.md` first.
Depends on Task 4 (`AnalysisResult`, `Onset`) and Task 2 models (`Beatmap`, `Note`,
`NoteKind`, `LaneKeyframe`, `ThemePalette`, `Difficulty`). Write tests FIRST.

## Files to create

- `AutoWave/Core/BeatmapKit/BeatmapGenerator.swift`
- `AutoWave/Core/BeatmapKit/DifficultyProfile.swift`
- `AutoWaveTests/BeatmapGeneratorTests.swift`

## Public interface (exact)

```swift
struct DifficultyProfile: Sendable {
    var maxNotesPerSecond: Double
    var strengthPercentile: Double
    var maxSimultaneous: Int
    var dragRatio: Double
    var movingDragRatio: Double
    var scrollSpeed: Double
    static func profile(for difficulty: Difficulty) -> DifficultyProfile
}
enum BeatmapGenerator {
    static let version = 1
    static func generate(from analysis: AnalysisResult, difficulty: Difficulty, seed: UInt64) -> Beatmap
}
```

Profile values (exact):

| difficulty | maxNotesPerSecond | strengthPercentile | maxSimultaneous | dragRatio | movingDragRatio | scrollSpeed |
|---|---|---|---|---|---|---|
| heaven | 0.8 | 85 | 1 | 0.10 | 0.0 | 250 |
| easy   | 1.5 | 65 | 1 | 0.15 | 0.2 | 320 |
| normal | 2.5 | 45 | 1 | 0.20 | 0.4 | 400 |
| hard   | 4.0 | 25 | 2 | 0.25 | 0.6 | 500 |
| hell   | 6.0 | 10 | 2 | 0.30 | 0.8 | 620 |

## Generation rules

- **RNG**: implement a small `SplitMix64` struct seeded with `seed`. All
  randomness goes through it — `generate` must be a pure function of
  (analysis, difficulty, seed).
- **Selection**: keep onsets with strength ≥ the profile's percentile of the
  strength distribution; then enforce `maxNotesPerSecond` with strength-ranked
  culling inside 1 s sliding windows (drop weakest first).
- **Lanes**: quantize onset spectral centroid into 4 buckets over the track's
  centroid range (low→lane 0 … high→lane 3), then add seeded jitter of ±1 lane
  with probability 0.25 to avoid streaks; clamp 0…3. `maxSimultaneous == 2`
  allows a second note on a different lane when two selected onsets fall
  within 30 ms (merge into a chord at the same time).
- **Drags**: an onset is drag-eligible when the gap to the next selected onset
  is ≥0.8 s. Convert eligible onsets to drags until the drag fraction reaches
  `dragRatio` (choose via RNG, deterministic order). Drag duration = min(gap −
  0.2 s, 4 s), snapped to the beat grid (60/tempo). Of drags, `movingDragRatio`
  fraction get a `lanePath` of 2–3 keyframes within ±1 lane of the start,
  clamped 0…3, offsets spread evenly across the duration.
- **No overlaps**: within one lane, a note may not start before the previous
  note (tap time, or drag end + 0.15 s) finishes.
- **Palette**: hue by dominant mean band — bass→0.72, mid→0.50, treble→0.08 —
  linearly interpolated between the top two bands by their dominance ratio;
  saturation 0.55–0.80 scaled by band spread (max−min normalized); brightness
  0.50–0.75 scaled by meanRMS (clamp). Set `generatorVersion = 1` and
  `tempo = analysis.tempo` on the returned Beatmap.

## Tests (write first)

Build a synthetic `AnalysisResult` fixture in code (e.g. 120 s, tempo 120,
onsets every 0.25 s with varying strengths/centroids — busy track):

1. **Determinism**: same input + same seed ⇒ two `generate` calls produce
   byte-identical JSON (`JSONEncoder` with `.sortedKeys`).
2. **Seed sensitivity**: different seeds ⇒ different note layouts (not equal).
3. **Density ordering**: note counts strictly increase heaven < easy < normal
   < hard < hell on the busy fixture.
4. **Lane bounds + no overlap**: all lanes in 0…3; per-lane no-overlap rule
   holds for every difficulty.
5. **Drags**: all drag durations > 0; hell on the busy fixture contains at
   least one drag with non-empty `lanePath`.
6. **Rate cap**: for each difficulty, no 1 s window contains more than
   `maxNotesPerSecond` notes (allow ceiling rounding: `Int(ceil(...))`).

## Verification & constraints

- `xcodegen generate`; typecheck what you can; orchestrator runs the full
  simulator test gate.
- BeatmapKit stays UI-framework-free. No third-party deps. No git. No
  Foundation `random` APIs — only the seeded SplitMix64.
