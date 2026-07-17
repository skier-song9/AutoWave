import Foundation

enum TempoEstimator {
    static func estimate(
        frames: [SpectralFrame],
        sampleRate: Double,
        hopSize: Int
    ) -> Double {
        guard frames.count > 1 else { return 0 }

        let minimumBPM = 60.0
        let maximumBPM = 200.0
        let minimumLag = max(
            1,
            Int(floor(60 * sampleRate / (Double(hopSize) * maximumBPM)))
        )
        let maximumLag = min(
            frames.count - 1,
            Int(ceil(60 * sampleRate / (Double(hopSize) * minimumBPM)))
        )
        guard minimumLag <= maximumLag else { return 0 }

        var correlations = [Float](repeating: 0, count: maximumLag + 1)
        var bestLag = 0
        var bestCorrelation: Float = 0
        for lag in minimumLag...maximumLag {
            var correlation: Float = 0
            let comparisonCount = frames.count - lag
            for index in 0..<comparisonCount {
                correlation += frames[index].flux * frames[index + lag].flux
            }
            correlation /= Float(comparisonCount)
            correlations[lag] = correlation
            if correlation > bestCorrelation {
                bestCorrelation = correlation
                bestLag = lag
            }
        }

        guard bestLag > 0, bestCorrelation > 0 else { return 0 }
        let halfLag = Int(round(Double(bestLag) / 2))
        if halfLag >= minimumLag,
           correlations[halfLag] >= bestCorrelation * 0.5 {
            bestLag = halfLag
        }
        var bpm = 60 * sampleRate / (Double(hopSize * bestLag))
        while bpm < minimumBPM {
            bpm *= 2
        }
        while bpm > maximumBPM {
            bpm /= 2
        }
        return bpm
    }
}
