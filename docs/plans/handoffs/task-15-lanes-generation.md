# Codex Handoff — Task 15: Variable lane count + harder, more musical beatmap generation

Read `AGENTS.md` first. Depends on Task 14 being merged (do not re-touch
JudgmentEngine scoring). This is the core "지옥 is too easy" fix. Owner
clarification: note TIMING is already precise — the problem is note DENSITY
(too few notes), PATTERN complexity (too monotonous), and lack of musical
mapping. BPM is mentioned to drive density, not to re-fix timing.

Read the current `AutoWave/Core/BeatmapKit/` (AnalysisResult, SpectralAnalyzer,
OnsetDetector, TempoEstimator, BeatmapGenerator, DifficultyProfile) and
`AutoWave/Core/Models/{Beatmap,Note}.swift`. Keep `BeatmapKit` UI-free and
deterministic (seeded SplitMix64). Bump `BeatmapGenerator.version` to 3.

## 1. Variable lane count per difficulty

Add `var laneCount: Int` to `DifficultyProfile` and `var laneCount: Int` to
`Beatmap` (Codable; decode default 4 for old maps — follow the existing
`themeID` decodeIfPresent pattern in Beatmap.swift). Lane counts:
- 천국 heaven 4, 쉬움 easy 4, 보통 normal 5, 어려움 hard 6, 지옥 hell 7.

All note lanes are `0 ..< laneCount`. `Note.lane` stays `Double`. Generator
must clamp/assign within the difficulty's lane count.

## 2. Harder density + profile retune

Raise density substantially and lower selectivity so hell is genuinely dense.
New `DifficultyProfile` values (also keep scrollSpeed roughly as-is or slightly
faster for higher tiers):

| diff | laneCount | maxNotesPerSecond | strengthPercentile | maxSimultaneous | dragRatio | movingDragRatio | scrollSpeed |
|---|---|---|---|---|---|---|---|
| heaven | 4 | 1.2 | 80 | 1 | 0.10 | 0.0 | 260 |
| easy   | 4 | 2.4 | 60 | 1 | 0.15 | 0.2 | 330 |
| normal | 5 | 4.0 | 40 | 2 | 0.20 | 0.4 | 420 |
| hard   | 6 | 6.5 | 20 | 2 | 0.25 | 0.6 | 520 |
| hell   | 7 | 9.5 | 8  | 2 | 0.30 | 0.8 | 640 |

`maxSimultaneous`: heaven/easy = 1 (never two notes at the same time — a drag
occupies the whole time-slot), normal/hard/hell = 2 (two concurrent notes
allowed, and one of them may be a drag while the other is a tap).

## 3. Beat grid + musical mapping (the substance)

Use tempo to build a beat grid: beat = 60/tempo. Subdivide per difficulty —
heaven/easy quantize onsets to 1/1 and 1/2 beats; normal to 1/2 and 1/4; hard
and hell to 1/4 and 1/8 (allow 1/8 streams on hell). Snap selected onsets to
the nearest grid subdivision time (this reflects BPM and produces musical,
on-grid patterns rather than raw onset jitter). Keep the note `time` on the
snapped grid value.

Lane assignment must be MUSICAL, not random jitter:
- Map each onset's spectral content to a lane region: low centroid / bass-heavy
  → left lanes, high centroid / treble-heavy → right lanes. Spread across the
  available `laneCount` by quantizing the centroid percentile into lane buckets.
- Add controlled variation with the seeded RNG so repeated same-lane streaks
  are broken, but keep it deterministic and keep the band→region tendency.
- Note TYPE by musical feature: sustained low-frequency energy spans (long
  inter-onset gap with continued bass energy) → drag notes; sharp broadband
  transients → taps. Respect `dragRatio` as a target fraction.

Pattern complexity by difficulty:
- heaven/easy: single notes, occasional straight drags, sparse.
- normal: add alternating-lane runs and short 1/4 bursts.
- hard: 1/8 partial streams, lane jumps, moving drags.
- hell: dense 1/8 streams, frequent 2-note chords/jacks, moving drags across
  several lanes, minimal rest. It should feel demanding.

## 4. New structural rules (from owner)

- **Simultaneity cap** enforced per difficulty (1 or 2 as above). When 2 is
  allowed, a tap+drag or tap+tap pair may share a time; never exceed 2.
- **Drag-span exclusion**: while a drag note is active (its `[time, time +
  duration]` window), NO tap note may appear in any lane between the drag's
  head lane and its tail lane, inclusive of the spanned range (compute lane
  span from `lane` + `lanePath`). Enforce during generation: after placing a
  drag, drop/relocate any tap that would fall inside the drag's time window AND
  within its lane span. This is the standard rhythm-game rule the owner cited
  (a 1→3 lane drag blocks taps in lanes 1..3 for its duration).
- Keep the existing no-overlap-within-a-lane rule.

## 5. Palette/theme

Theme selection (Task 11 `GameTheme.select`) stays; keep storing `themeID` and
`palette`. Just ensure the generator still populates them.

## 6. Tests

Update `AutoWaveTests/BeatmapGeneratorTests.swift` and keep determinism +
ordering guarantees, plus NEW assertions:
- laneCount per difficulty is correct; all note lanes within `0..<laneCount`.
- density strictly increases heaven<easy<normal<hard<hell on a busy fixture,
  and hell note count is now substantially higher than before (e.g. on a 60 s
  120-BPM busy fixture, hell yields clearly more notes than hard — assert a
  ratio, not a brittle absolute).
- simultaneity: no time has >1 note for heaven/easy, >2 for the rest.
- drag-span exclusion: for every drag, assert no tap exists within its time
  window and lane span.
- notes snap to the beat grid (times are near-multiples of the subdivision).
- determinism (same analysis+seed ⇒ byte-identical JSON) still holds; old-JSON
  decode default for `laneCount`.

## Verification

- `xcodegen generate` if files added. Typecheck only; orchestrator runs the
  gate. Note: GameScene currently assumes 4 lanes — it will be updated in Task
  16 to read `beatmap`/`profile` laneCount. Do NOT break the build: if GameScene
  references a hardcoded 4, leave a `laneCount` accessor on the beatmap/profile
  it can adopt, but you may leave the scene rendering as-is for now as long as
  it compiles (Task 16 does the visual N-lane work).
