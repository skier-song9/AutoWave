import Foundation

enum OnsetBand: Sendable, Equatable {
    case low
    case mid
    case high
}

struct Onset: Sendable {
    var time: TimeInterval
    var strength: Float
    var bass: Float
    var mid: Float
    var treble: Float
    var centroid: Float
    var band: OnsetBand

    init(
        time: TimeInterval,
        strength: Float,
        bass: Float,
        mid: Float,
        treble: Float,
        centroid: Float,
        band: OnsetBand? = nil
    ) {
        self.time = time
        self.strength = strength
        self.bass = bass
        self.mid = mid
        self.treble = treble
        self.centroid = centroid
        self.band = band ?? Self.dominantBand(bass: bass, mid: mid, treble: treble)
    }

    private static func dominantBand(bass: Float, mid: Float, treble: Float) -> OnsetBand {
        if bass >= mid, bass >= treble {
            return .low
        }
        if mid >= treble {
            return .mid
        }
        return .high
    }
}

struct AnalysisResult: Sendable {
    var duration: TimeInterval
    var tempo: Double
    var onsets: [Onset]
    var meanBass: Float
    var meanMid: Float
    var meanTreble: Float
    var meanRMS: Float
    var intensityCurve: [Float]

    init(
        duration: TimeInterval,
        tempo: Double,
        onsets: [Onset],
        meanBass: Float,
        meanMid: Float,
        meanTreble: Float,
        meanRMS: Float,
        intensityCurve: [Float] = []
    ) {
        self.duration = duration
        self.tempo = tempo
        self.onsets = onsets
        self.meanBass = meanBass
        self.meanMid = meanMid
        self.meanTreble = meanTreble
        self.meanRMS = meanRMS
        self.intensityCurve = intensityCurve
    }
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

        let tempo = TempoEstimator.estimate(
            frames: spectral.frames,
            sampleRate: decoded.sampleRate,
            hopSize: SpectralAnalyzer.hopSize
        )
        let onsets = OnsetDetector.detect(
            frames: spectral.frames,
            sampleRate: decoded.sampleRate,
            hopSize: SpectralAnalyzer.hopSize,
            tempo: tempo
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

        let intensityCurve = makeIntensityCurve(
            frames: spectral.frames,
            onsets: onsets,
            duration: decoded.duration,
            sampleRate: decoded.sampleRate,
            hopSize: SpectralAnalyzer.hopSize
        )

        progress?(1)
        return AnalysisResult(
            duration: decoded.duration,
            tempo: tempo,
            onsets: onsets,
            meanBass: meanBass,
            meanMid: meanMid,
            meanTreble: meanTreble,
            meanRMS: meanRMS,
            intensityCurve: intensityCurve
        )
    }

    private static func makeIntensityCurve(
        frames: [SpectralFrame],
        onsets: [Onset],
        duration: TimeInterval,
        sampleRate: Double,
        hopSize: Int
    ) -> [Float] {
        let secondCount = max(1, Int(ceil(duration)))
        guard !frames.isEmpty else {
            return Array(repeating: 0, count: secondCount)
        }

        var rmsTotals = Array(repeating: 0.0, count: secondCount)
        var rmsCounts = Array(repeating: 0, count: secondCount)
        for (index, frame) in frames.enumerated() {
            let second = min(
                secondCount - 1,
                Int((Double(index * hopSize) / sampleRate).rounded(.down))
            )
            rmsTotals[second] += Double(frame.rms)
            rmsCounts[second] += 1
        }

        var onsetDensity = Array(repeating: 0.0, count: secondCount)
        for onset in onsets {
            let second = min(secondCount - 1, max(0, Int(onset.time.rounded(.down))))
            onsetDensity[second] += 1
        }

        let rms = rmsTotals.enumerated().map { index, total in
            rmsCounts[index] > 0 ? total / Double(rmsCounts[index]) : 0
        }
        let normalizedRMS = normalize(rms)
        let normalizedDensity = normalize(onsetDensity)
        let combined = zip(normalizedRMS, normalizedDensity).map { rms, density in
            0.6 * rms + 0.4 * density
        }

        let radius = 2
        let smoothed = combined.indices.map { index in
            let lower = max(0, index - radius)
            let upper = min(combined.count - 1, index + radius)
            let values = combined[lower...upper]
            return values.reduce(0, +) / Float(values.count)
        }
        return normalize(smoothed)
    }

    private static func normalize(_ values: [Double]) -> [Float] {
        guard let minimum = values.min(), let maximum = values.max(), maximum > minimum else {
            return Array(repeating: values.isEmpty ? 0 : 1, count: values.count)
        }
        return values.map { Float(($0 - minimum) / (maximum - minimum)) }
    }

    private static func normalize(_ values: [Float]) -> [Float] {
        guard let minimum = values.min(), let maximum = values.max(), maximum > minimum else {
            return Array(repeating: values.isEmpty ? 0 : 1, count: values.count)
        }
        return values.map { ($0 - minimum) / (maximum - minimum) }
    }
}
