# Codex Handoff — Task 22: Beatmap generation quality overhaul (musical, dense, full-song)

Read `AGENTS.md` first. BeatmapKit stays UI-free, deterministic (SplitMix64),
fully unit-tested. Bump generator version to 5. Owner verdict on current maps:
"FFT/onset 품질 낮음, 음원과 무관하게 비슷한 패턴 반복, 강약·주파수 변화
미반영, 노트 수 지나치게 적음, 일부 음원은 노트가 아예 안 나옴." This task is
the substance — apply real rhythm-game charting techniques.

## 0. Version-aware regeneration (stale-map fix)

`AnalysisViewModel` (or Library flow) must detect stored beatmaps whose
`generatorVersion < BeatmapGenerator.version` and regenerate all difficulties
automatically before play (silent re-run of the stored analysis→generate path;
re-analyze the audio file since AnalysisResult isn't persisted). Old imports
must pick up every future tuning without delete/re-import.

## 1. Analysis upgrades (SpectralAnalyzer/OnsetDetector)

Implement multi-band onset detection (this is what real charters/auto-mappers
use — SuperFlux-style):
- Compute spectral flux separately in 3 bands: low (<160 Hz, kick), mid
  (160–2000 Hz, snare/vocal), high (>4 kHz, hats).
- Per-band adaptive threshold (sliding median as now) with LOWER selectivity:
  the current global tuning drops too many onsets ("노트 수 지나치게 적음",
  "일부 음원 노트 0개"). After per-band peak-picking, merge band onsets
  (±25 ms merge window) tagging each with its dominant band.
- Add a maximum-filter vibrato suppression across ±2 frequency bins before
  flux (SuperFlux trick) to avoid false onsets on sustained vocals while
  keeping percussive hits.
- Fallback guarantee: if a track still yields < 0.5 onsets/sec average,
  synthesize beat-grid onsets from the tempo estimate (place onsets on every
  beat with strength from local RMS) so NO track ever produces an empty map.
- Keep `analyze` covering the FULL file (Task 19 added a coverage test).

## 2. Musical structure → density (강약 반영)

- Compute a per-second intensity curve (RMS + onset density, smoothed ~4 s).
- Normalize into 0…1 and use it to modulate local note density: quiet
  sections thin out (keep only strongest onsets), loud sections use the full
  difficulty budget. This produces verse/chorus dynamics instead of uniform
  patterns ("비슷한 패턴 반복" fix).

## 3. Pattern generation rework

Keep the beat grid + band→lane tendency, but replace the monotonous output:
- **Kick onsets (low band)** → left-region lanes, prefer 2-note chords on
  strong kicks (hard/hell).
- **Snare/clap (mid)** → alternating middle lanes; backbeat feel.
- **Hats/high** → right-region short streams on 1/8 (hard/hell) or 1/4
  (normal).
- **Sustained energy** (long low/mid energy without new onsets) → drag notes
  along the sustain length (respect drag caps and span-exclusion).
- Anti-repetition: track the last 8 lane choices; if a lane pattern (e.g.
  1-2-3-4 run or same-lane jack) repeats more than twice consecutively,
  force a variation via seeded RNG (mirror the run, or displace by ±1 lane).
  This directly addresses "대부분 4개 단일 노트 연속 반복".
- Respect: min gap between notes in the SAME lane ≥ 0.12 s (heaven/easy
  0.25 s); global simultaneity caps and drag rules unchanged.
- Density guardrails per difficulty stay (maxNotesPerSecond), but the
  strengthPercentile selection should now operate per-intensity-window, not
  globally.

## 4. Owner-set constraints (keep/verify)

- First note at ≥ 3.0 s into the track (owner item 26 — already satisfied per
  owner, but make it an explicit generator rule + test so it never regresses).
- Global minimum inter-onset spacing before placement: merge onsets closer
  than 90 ms (~15–30 ms wider than the old 75 ms effective minimum — owner
  items 10/11) EXCEPT intentional chord groups (same-time events allowed).
- Fall speed: reduce base scrollSpeed ~15% across difficulties (owner item 12
  "너무 빠름"): heaven 220, easy 280, normal 360, hard 440, hell 545. (The
  user speed multiplier from Task 21 scales on top.)

## 5. Tests

Extend BeatmapGeneratorTests + analysis tests:
- Multi-band: kick-only fixture maps to left-region lanes; hat bursts to
  right-region; mixed fixture produces both.
- Empty-map guarantee: near-silent 60 s fixture still yields ≥ 0.5 notes/sec
  on normal via beat-grid fallback.
- Intensity modulation: fixture with quiet first half / loud second half ⇒
  second-half note count strictly greater.
- Anti-repetition: on a uniform click fixture, no lane appears > 2 times
  consecutively and no strictly repeating 4-lane cycle longer than 2 cycles.
- First note ≥ 3.0 s; same-lane min gaps hold; determinism (seed ⇒
  byte-identical) still holds; full-song coverage (notes in last 10 s of a
  120 s fixture).
- Version regen: entity with generatorVersion 4 triggers regeneration path in
  AnalysisViewModel (unit-test the decision function).

## Verification

`xcodegen generate` if needed. Orchestrator runs build+tests only (owner
verifies by playing — no code review). Re-read your diff yourself. Determinism
and BeatmapKit purity are non-negotiable.
