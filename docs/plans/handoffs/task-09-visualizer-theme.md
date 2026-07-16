# Codex Handoff — Task 9: Audio-reactive background + theme

Read `AGENTS.md` and the Task 9 section of `docs/plans/2026-07-17-autowave-mvp.md`
first. Extends Tasks 6–8 output — read merged sources in
`AutoWave/Features/Gameplay/` and `AutoWave/Core/` before coding.

## Files

- Create: `AutoWave/Core/AudioEngine/VisualizerTap.swift`
- Modify: `AutoWave/Features/Gameplay/GameScene.swift`
- Modify: `AutoWave/Features/Analysis/AnalysisView.swift`,
  `AutoWave/Features/Library/LibraryView.swift` (palette accents only)

## VisualizerTap

- Installs a tap on the gameplay `AVAudioEngine.mainMixerNode` (1024-frame
  buffers): vDSP 1024-pt FFT → 16 log-spaced bands (cover ~40 Hz–8 kHz) →
  per-band magnitude, smoothed with exponential moving average (attack fast
  ~0.3, release slow ~0.85 so bars fall gently).
- Publishes `bands: [Float]` (16 values, 0…1 normalized) at ~30 Hz max —
  coalesce buffer callbacks; never publish from the audio thread directly
  (hop to main via `DispatchQueue.main.async` or an AsyncStream consumed on
  main).
- **Audio-thread safety**: the tap block does DSP into preallocated buffers
  only — no allocation, no locks shared with UI, no Objective-C messaging that
  can block. UI reads only the published snapshot.
- API: `final class VisualizerTap` with `attach(to engine: AVAudioEngine)`,
  `detach()`, and an observable `bands` property (`@Observable` or a
  `@MainActor` published holder — match project style from Task 6's
  view model).

## GameScene background

- Replace the solid palette tint with a **ripple field**: 5–7 concentric ring
  nodes centered low-center-screen, expanding outward and fading (water
  rings); ring spawn rate and expansion amplitude driven by bass bands
  (bands[0..3] mean), ring stroke width/alpha by mid bands; a faint full-screen
  hue overlay whose brightness follows overall level.
- All colors from `Beatmap.palette` hue family (vary brightness/saturation
  only; hue stays within ±0.06 of palette hue).
- **Game start wash-in**: 0.8 s animation on scene start — background fades
  from neutral dark to the palette color while the first rings bloom.
- Performance: rings are pooled SKShapeNodes; band updates mutate existing
  nodes; zero allocation in `update(_:)`; target 60 fps alongside note
  rendering.

## Library/Analysis accents

- `LibraryView` rows: leading capsule/dot tinted with the track's palette
  (decode one stored `BeatmapEntity` lazily — any difficulty, they share the
  palette; fall back to accent color when no beatmap yet).
- `AnalysisView`: ripple progress animation tinted with the generated palette
  once analysis completes (before that, accent color).
- Shared helper: `ThemePalette.color` computed property (SwiftUI `Color`) in a
  small extension file under `AutoWave/Core/Models/` (UI extension may live in
  the Features layer if keeping Core UI-free — put it in
  `AutoWave/Features/` shared spot, e.g. `AutoWave/Features/ThemePalette+Color.swift`).

## Verification & constraints

- `xcodegen generate`; typecheck; orchestrator runs simulator gate + manual
  smoke run (visualizer visibly reacts, no frame drops, no audio glitches).
- No unit tests required for the tap (audio-thread code); keep any pure math
  (band mapping) in a testable function and add a small test if trivial.
- No third-party deps. No git. UI strings Korean.
