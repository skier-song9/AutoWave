import Foundation

enum OnsetDetector {
    static let medianWindowSize = 11
    static let medianMultiplier: Float = 1.15
    static let globalMedianMultiplier: Float = 2
    static let minimumGap: TimeInterval = 0.09
    static let mergeWindow: TimeInterval = 0.025

    private struct Peak {
        var index: Int
        var value: Float
        var band: OnsetBand
    }

    static func detect(
        frames: [SpectralFrame],
        sampleRate: Double,
        hopSize: Int,
        tempo: Double = 0
    ) -> [Onset] {
        guard !frames.isEmpty else { return [] }

        let bands: [OnsetBand] = [.low, .mid, .high]
        let bandPeaks = bands.flatMap { band in
            peaks(
                for: frames,
                band: band,
                sampleRate: sampleRate,
                hopSize: hopSize
            )
        }
        let merged = merge(bandPeaks, frames: frames, sampleRate: sampleRate, hopSize: hopSize)
        let duration = Double(frames.count * hopSize) / sampleRate
        let averageRMS = frames.map(\.rms).reduce(0, +) / Float(frames.count)
        let onsetRate = duration > 0 ? Double(merged.count) / duration : 0
        if onsetRate < 0.5, averageRMS < 0.01, duration >= 4 {
            return fallbackBeatGrid(
                frames: frames,
                sampleRate: sampleRate,
                hopSize: hopSize,
                tempo: tempo
            )
        }
        return merged
    }

    private static func peaks(
        for frames: [SpectralFrame],
        band: OnsetBand,
        sampleRate: Double,
        hopSize: Int
    ) -> [Peak] {
        let values = frames.map { flux(for: $0, band: band) }
        let halfWindow = medianWindowSize / 2
        let minimumGapFrames = max(
            1,
            Int(ceil(minimumGap * sampleRate / Double(hopSize)))
        )
        let sortedValues = values.sorted()
        let globalMedian = sortedValues[sortedValues.count / 2]
        let globalNoiseFloor = globalMedian * globalMedianMultiplier
        let maximumValue = values.max() ?? 0
        guard maximumValue > 0 else { return [] }

        var medianValues = [Float](repeating: 0, count: medianWindowSize)
        var peakIndices: [Int] = []
        peakIndices.reserveCapacity(values.count / minimumGapFrames)
        for index in values.indices {
            var medianCount = 0
            for offset in -halfWindow...halfWindow {
                let sampleIndex = min(values.count - 1, max(0, index + offset))
                medianValues[medianCount] = values[sampleIndex]
                medianCount += 1
            }
            medianValues.sort()
            let threshold = max(
                medianValues[halfWindow] * medianMultiplier,
                globalNoiseFloor,
                maximumValue * 0.05
            )
            let value = values[index]
            guard value > threshold else { continue }

            let previousValue = index > 0 ? values[index - 1] : -.infinity
            let nextValue = index + 1 < values.count ? values[index + 1] : -.infinity
            guard value >= previousValue, value >= nextValue,
                  value > previousValue || value > nextValue else { continue }

            if let previousPeak = peakIndices.last,
               index - previousPeak < minimumGapFrames {
                if value > values[previousPeak] {
                    peakIndices[peakIndices.count - 1] = index
                }
            } else {
                peakIndices.append(index)
            }
        }

        return peakIndices.map {
            Peak(index: $0, value: values[$0] / maximumValue, band: band)
        }
    }

    private static func merge(
        _ peaks: [Peak],
        frames: [SpectralFrame],
        sampleRate: Double,
        hopSize: Int
    ) -> [Onset] {
        guard !peaks.isEmpty else { return [] }
        let sortedPeaks = peaks.sorted {
            if $0.index == $1.index {
                return $0.value > $1.value
            }
            return $0.index < $1.index
        }
        var groups: [[Peak]] = []
        for peak in sortedPeaks {
            if let last = groups.last,
               let lastPeak = last.max(by: { $0.value < $1.value }),
               time(for: peak.index, sampleRate: sampleRate, hopSize: hopSize)
                    - time(for: lastPeak.index, sampleRate: sampleRate, hopSize: hopSize)
                    <= mergeWindow {
                groups[groups.count - 1].append(peak)
            } else {
                groups.append([peak])
            }
        }

        let maximumStrength = groups
            .compactMap { $0.max(by: { $0.value < $1.value })?.value }
            .max() ?? 1
        return groups.compactMap { group in
            guard let peak = group.max(by: { $0.value < $1.value }) else { return nil }
            let frame = frames[peak.index]
            return Onset(
                time: time(for: peak.index, sampleRate: sampleRate, hopSize: hopSize),
                strength: peak.value / maximumStrength,
                bass: frame.bass,
                mid: frame.mid,
                treble: frame.treble,
                centroid: frame.centroid,
                band: peak.band
            )
        }
    }

    private static func fallbackBeatGrid(
        frames: [SpectralFrame],
        sampleRate: Double,
        hopSize: Int,
        tempo: Double
    ) -> [Onset] {
        let beat = 60 / (tempo > 0 ? tempo : 120)
        let duration = Double(frames.count * hopSize) / sampleRate
        guard beat > 0, duration > 0 else { return [] }

        var result: [Onset] = []
        var time = 0.0
        while time <= duration + 1e-9 {
            let frameIndex = min(
                frames.count - 1,
                max(0, Int(round(time * sampleRate / Double(hopSize))))
            )
            let frame = frames[frameIndex]
            result.append(
                Onset(
                    time: time,
                    strength: frame.rms,
                    bass: frame.bass,
                    mid: frame.mid,
                    treble: frame.treble,
                    centroid: frame.centroid
                )
            )
            time += beat
        }
        return result
    }

    private static func flux(for frame: SpectralFrame, band: OnsetBand) -> Float {
        let totalEnergy = max(0.0001, frame.bass + frame.mid + frame.treble)
        let minimumBandShare: Float = 0.05
        switch band {
        case .low:
            let share = frame.bass / totalEnergy
            guard share >= minimumBandShare else { return 0 }
            return frame.lowFlux * share * share
        case .mid:
            let share = frame.mid / totalEnergy
            guard share >= minimumBandShare else { return 0 }
            return frame.midFlux * share * share
        case .high:
            let share = frame.treble / totalEnergy
            guard share >= minimumBandShare else { return 0 }
            return frame.highFlux * share * share
        }
    }

    private static func time(for index: Int, sampleRate: Double, hopSize: Int) -> TimeInterval {
        TimeInterval((index + 1) * hopSize) / sampleRate
    }
}
