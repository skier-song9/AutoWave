# Codex Handoff — Task 4: BeatmapKit analysis (decode → onsets/tempo/features)

Read `AGENTS.md` and the Task 4 section of `docs/plans/2026-07-17-autowave-mvp.md` first.
Implement exactly this task. Write tests FIRST, then implement until green.

## Files to create

- `AutoWave/Core/BeatmapKit/AudioDecoder.swift`
- `AutoWave/Core/BeatmapKit/SpectralAnalyzer.swift`
- `AutoWave/Core/BeatmapKit/OnsetDetector.swift`
- `AutoWave/Core/BeatmapKit/TempoEstimator.swift`
- `AutoWave/Core/BeatmapKit/AnalysisResult.swift`
- `AutoWaveTests/BeatmapKitAnalysisTests.swift`

## Public interface (exact — later tasks depend on it)

```swift
struct Onset: Sendable {
    var time: TimeInterval; var strength: Float
    var bass: Float; var mid: Float; var treble: Float; var centroid: Float
}
struct AnalysisResult: Sendable {
    var duration: TimeInterval; var tempo: Double
    var onsets: [Onset]
    var meanBass: Float; var meanMid: Float; var meanTreble: Float; var meanRMS: Float
}
enum BeatmapKit {
    static func analyze(fileAt url: URL, progress: (@Sendable (Double) -> Void)?) async throws -> AnalysisResult
}
```

## Algorithm requirements

- **AudioDecoder**: `AVAudioFile` → mono Float32 PCM at 22_050 Hz via `AVAudioConverter`.
  Handle arbitrary input formats (m4a/mp3/wav, any sample rate, stereo→mono mix).
- **SpectralAnalyzer** (Accelerate/vDSP): 1024-pt FFT, hop 512, Hann window.
  Per frame: log-magnitude spectrum (`log(1 + magnitude)`), spectral flux
  (half-wave-rectified positive difference vs previous frame, summed), band
  energies bass <250 Hz / mid 250–2000 Hz / treble >2000 Hz, spectral centroid
  (Hz), RMS. Preallocate all buffers; no per-frame allocation.
- **OnsetDetector**: flux curve → adaptive threshold = 1.5 × sliding median
  (window 11 frames) → local-maximum peak picking with minimum gap 0.1 s.
  Onset time = frame index × hop / sampleRate. Strength = flux value at peak,
  normalized 0…1 over the track. Per-onset bass/mid/treble/centroid sampled at
  the peak frame.
- **TempoEstimator**: autocorrelation of the flux envelope, search 60–200 BPM,
  fold octave errors (if best lag ≙ <60 or >200, halve/double into range).
- **BeatmapKit.analyze**: orchestrates decode → frames → onsets → tempo; calls
  `progress` with 0…1 (decode ≈ 0–0.3, spectral ≈ 0.3–0.8, rest to 1.0);
  runs off the calling actor (it is `async`); throws on unreadable file.

## Tests (write these first)

In `AutoWaveTests/BeatmapKitAnalysisTests.swift`, synthesize WAV fixtures at
runtime into `FileManager.default.temporaryDirectory` (use `AVAudioFile` to
write Float32 buffers):

1. **Click track**: 20 s of silence with a 1-frame full-scale impulse (or 5 ms
   noise burst) every 0.5 s (= 120 BPM). Assert: every click matched by an
   onset within ±30 ms; onset count within ±2 of expected; tempo within
   120 ± 3 BPM.
2. **Sustained sine**: 10 s constant-amplitude 440 Hz sine. Assert ≤2 onsets
   total (attack may produce one).
3. **Band dominance**: alternating 100 Hz bursts vs 4000 Hz bursts (0.2 s on /
   0.3 s off). Assert onsets from the low section have bass > treble and vice
   versa; sine-burst track's meanBass/meanTreble reflect the same ordering.

## Verification

- `xcodegen generate` after adding files.
- Compile/typecheck what you can. If simulator access fails in your sandbox,
  say so; the orchestrator runs:
  `env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project AutoWave.xcodeproj -scheme AutoWave -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`

## Constraints

- `BeatmapKit` sources import Foundation/AVFoundation/Accelerate only — no
  SwiftUI/UIKit/SpriteKit/SwiftData.
- Deterministic: no randomness anywhere in this task.
- No third-party deps. No git commands. Identifiers/comments English.
