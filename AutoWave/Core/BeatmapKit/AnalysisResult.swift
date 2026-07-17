import Foundation

struct Onset: Sendable {
    var time: TimeInterval
    var strength: Float
    var bass: Float
    var mid: Float
    var treble: Float
    var centroid: Float
}

struct AnalysisResult: Sendable {
    var duration: TimeInterval
    var tempo: Double
    var onsets: [Onset]
    var meanBass: Float
    var meanMid: Float
    var meanTreble: Float
    var meanRMS: Float
}

enum BeatmapKit {
    static func analyze(
        fileAt url: URL,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> AnalysisResult {
        try await Task.detached {
            try analyzeSynchronously(fileAt: url, progress: progress)
        }.value
    }

    private static func analyzeSynchronously(
        fileAt url: URL,
        progress: (@Sendable (Double) -> Void)?
    ) throws -> AnalysisResult {
        progress?(0)
        let decoded = try AudioDecoder.decode(fileAt: url) { fraction in
            progress?(fraction * 0.3)
        }
        progress?(0.3)

        let spectral = SpectralAnalyzer.analyze(decoded.samples) { fraction in
            progress?(0.3 + fraction * 0.5)
        }
        progress?(0.8)

        let onsets = OnsetDetector.detect(
            frames: spectral.frames,
            sampleRate: decoded.sampleRate,
            hopSize: SpectralAnalyzer.hopSize
        )
        let tempo = TempoEstimator.estimate(
            frames: spectral.frames,
            sampleRate: decoded.sampleRate,
            hopSize: SpectralAnalyzer.hopSize
        )

        let frameCount = Float(spectral.frames.count)
        let meanBass: Float
        let meanMid: Float
        let meanTreble: Float
        let meanRMS: Float
        if frameCount == 0 {
            meanBass = 0
            meanMid = 0
            meanTreble = 0
            meanRMS = 0
        } else {
            var bass = Float.zero
            var mid = Float.zero
            var treble = Float.zero
            var rms = Float.zero
            for frame in spectral.frames {
                bass += frame.bass
                mid += frame.mid
                treble += frame.treble
                rms += frame.rms
            }
            meanBass = bass / frameCount
            meanMid = mid / frameCount
            meanTreble = treble / frameCount
            meanRMS = rms / frameCount
        }

        progress?(1)
        return AnalysisResult(
            duration: decoded.duration,
            tempo: tempo,
            onsets: onsets,
            meanBass: meanBass,
            meanMid: meanMid,
            meanTreble: meanTreble,
            meanRMS: meanRMS
        )
    }
}
