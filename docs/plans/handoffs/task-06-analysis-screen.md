# Codex Handoff — Task 6: Analysis screen (convert + persist)

Read `AGENTS.md` and the Task 6 section of `docs/plans/2026-07-17-autowave-mvp.md` first.
Depends on Tasks 2–5: `TrackEntity`/`BeatmapEntity`, `BeatmapKit.analyze`,
`BeatmapGenerator.generate`. Check the actual merged signatures in
`AutoWave/Core/` before coding — they are the source of truth.

## Files

- Rewrite: `AutoWave/Features/Analysis/AnalysisView.swift`
- Create: `AutoWave/Features/Analysis/AnalysisViewModel.swift`
- Test: `AutoWaveTests/AnalysisViewModelTests.swift`

## Behavior

- `AnalysisViewModel` (`@Observable`, `@MainActor` for published state):
  - `state`: enum `idle / analyzing(progress: Double) / generating(current: Int, total: Int) / done / failed(message: String)`.
  - `start(track: TrackEntity, context: ModelContext) async`:
    1. `BeatmapKit.analyze(fileAt: track.audioURL)` off the main actor,
       progress callback drives `analyzing(progress:)` (hop to main).
    2. For each of the 5 difficulties in order (heaven, easy, normal, hard,
       hell): `BeatmapGenerator.generate(from:difficulty:seed:)`, update
       `generating(current:total:)`.
    3. **Seed**: stable per track — FNV-1a 64-bit hash of
       `track.sourceFilename` + `-` + audio file byte count. Same track ⇒ same
       seed every run.
    4. Delete any existing `BeatmapEntity`s for the track, then insert the 5
       new ones (JSON-encode `Beatmap` into `beatmapData`), save context,
       set `done`.
    5. Any thrown error ⇒ `failed(message:)` with a Korean user-facing message
       ("분석에 실패했어요").
- `AnalysisView(track:)`: ripple-styled progress UI — concentric expanding
  circles animation while working (pure SwiftUI, e.g. animated `Circle`
  strokes scaling/fading; subtle, water-like). Korean copy: "분석 중…" during
  analyzing (+ percent), "비트맵 생성 중… (n/5)" during generating, "완료!" on
  done with a "라이브러리로" button that dismisses. Starts automatically via
  `.task { }` on appear. Failed state shows message + "다시 시도" button.

## Tests

`AnalysisViewModelTests` with an in-memory ModelContainer:

1. Write a tiny valid WAV (1–2 s, e.g. clicks) to temp dir; create a
   `TrackEntity` whose `relativeAudioPath` resolves to it (set the relative
   path so `audioURL` points at the file — if `audioURL` is hardwired to
   Application Support, write the fixture under the real Application Support
   dir in the test and clean up after).
2. Run `await viewModel.start(track:context:)`; assert state ends `done`, and
   exactly 5 `BeatmapEntity`s exist for the track, one per difficulty, each
   decoding into a valid `Beatmap` with matching difficulty.
3. Re-run `start` on the same track: still exactly 5 entities (replace, not
   append), and identical `beatmapData` bytes (seed stability).

## Verification & constraints

- `xcodegen generate`; typecheck what you can; orchestrator runs the full
  simulator test gate.
- Concurrency: no data races — analysis runs detached/nonisolated, UI state
  mutations on MainActor only. Swift 6 strict concurrency must compile clean.
- No third-party deps. No git. UI strings Korean, identifiers English.
