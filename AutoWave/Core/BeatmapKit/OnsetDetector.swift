import Foundation

enum OnsetDetector {
    static let medianWindowSize = 11
    static let medianMultiplier: Float = 1.5
    static let globalMedianMultiplier: Float = 4
    static let minimumGap: TimeInterval = 0.1

    static func detect(
        frames: [SpectralFrame],
        sampleRate: Double,
        hopSize: Int
    ) -> [Onset] {
        guard !frames.isEmpty else { return [] }

        let halfWindow = medianWindowSize / 2
        let minimumGapFrames = max(
            1,
            Int(ceil(minimumGap * sampleRate / Double(hopSize)))
        )
        var medianValues = [Float](repeating: 0, count: medianWindowSize)
        var peakIndices: [Int] = []
        peakIndices.reserveCapacity(frames.count / minimumGapFrames)
        var sortedFlux = frames.map(\.flux)
        sortedFlux.sort()
        let globalNoiseFloor = sortedFlux[sortedFlux.count / 2] * globalMedianMultiplier
        let maximumFlux = frames.map(\.flux).max() ?? 0

        for index in frames.indices {
            var medianCount = 0
            for offset in -halfWindow...halfWindow {
                let sampleIndex = min(
                    frames.count - 1,
                    max(0, index + offset)
                )
                medianValues[medianCount] = frames[sampleIndex].flux
                medianCount += 1
            }
            medianValues.sort()
            let threshold = max(
                medianValues[halfWindow] * medianMultiplier,
                globalNoiseFloor
            )
            let flux = frames[index].flux
            guard flux > threshold else { continue }

            let previousFlux = index > 0 ? frames[index - 1].flux : -.infinity
            let nextFlux = index + 1 < frames.count ? frames[index + 1].flux : -.infinity
            guard flux >= previousFlux, flux >= nextFlux,
                  flux > previousFlux || flux > nextFlux else { continue }

            if let previousPeak = peakIndices.last,
               index - previousPeak < minimumGapFrames {
                if flux > frames[previousPeak].flux {
                    peakIndices[peakIndices.count - 1] = index
                }
            } else {
                peakIndices.append(index)
            }
        }

        return peakIndices.map { index in
            let frame = frames[index]
            return Onset(
                time: TimeInterval(index * hopSize) / sampleRate,
                strength: maximumFlux > 0 ? frame.flux / maximumFlux : 0,
                bass: frame.bass,
                mid: frame.mid,
                treble: frame.treble,
                centroid: frame.centroid
            )
        }
    }
}
