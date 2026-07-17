import Foundation

enum BeatmapGenerator {
    static let version = 1

    static func generate(from analysis: AnalysisResult, difficulty: Difficulty, seed: UInt64) -> Beatmap {
        let profile = DifficultyProfile.profile(for: difficulty)
        var rng = SplitMix64(seed: seed)
        let indexedOnsets = analysis.onsets.enumerated().map {
            IndexedOnset(index: $0.offset, onset: $0.element)
        }
        let selected = selectOnsets(indexedOnsets, profile: profile)
        let dragSources = chooseDragSources(from: selected, ratio: profile.dragRatio, rng: &rng)
        let movingSources = chooseMovingSources(
            from: dragSources,
            ratio: profile.movingDragRatio,
            rng: &rng
        )
        let centroidRange = centroidRange(in: analysis.onsets)
        let groups = makeGroups(selected, maxSimultaneous: profile.maxSimultaneous)

        var candidates: [GeneratedNote] = []
        candidates.reserveCapacity(selected.count)
        for group in groups {
            var lanes: [Int] = []
            for item in group {
                var lane = quantizedLane(
                    for: item.onset.centroid,
                    in: centroidRange
                )
                if rng.nextDouble() < 0.25 {
                    lane += rng.nextDouble() < 0.5 ? -1 : 1
                    lane = min(3, max(0, lane))
                }
                if lanes.contains(lane) {
                    lane = (0...3).first { !lanes.contains($0) } ?? lane
                }
                lanes.append(lane)

                let duration: TimeInterval
                if dragSources.contains(item.index), let next = nextOnset(after: item, in: selected) {
                    duration = snappedDuration(
                        gap: next.onset.time - item.onset.time,
                        tempo: analysis.tempo
                    )
                } else {
                    duration = 0
                }

                let path: [LaneKeyframe]
                if duration > 0, movingSources.contains(item.index) {
                    path = makeLanePath(
                        startLane: lane,
                        duration: duration,
                        rng: &rng
                    )
                } else {
                    path = []
                }

                candidates.append(
                    GeneratedNote(
                        kind: duration > 0 ? .drag : .tap,
                        time: item.onset.time,
                        lane: lane,
                        duration: duration,
                        lanePath: path
                    )
                )
            }
        }

        let notes = removeOverlaps(from: candidates).enumerated().map { index, candidate in
            Note(
                id: makeID(seed: seed, index: index),
                kind: candidate.kind,
                time: candidate.time,
                lane: Double(candidate.lane),
                duration: candidate.duration,
                lanePath: candidate.lanePath
            )
        }

        return Beatmap(
            difficulty: difficulty,
            tempo: analysis.tempo,
            notes: notes,
            palette: makePalette(from: analysis),
            generatorVersion: version
        )
    }

    private struct IndexedOnset {
        var index: Int
        var onset: Onset
    }

    private struct GeneratedNote {
        var kind: NoteKind
        var time: TimeInterval
        var lane: Int
        var duration: TimeInterval
        var lanePath: [LaneKeyframe]
    }

    private struct Band {
        var value: Double
        var hue: Double
        var order: Int
    }

    private static func selectOnsets(
        _ onsets: [IndexedOnset],
        profile: DifficultyProfile
    ) -> [IndexedOnset] {
        guard !onsets.isEmpty else { return [] }
        let strengths = onsets.map { $0.onset.strength }.sorted()
        let threshold = percentileValue(strengths, percentile: profile.strengthPercentile)
        let thresholded = onsets.filter { $0.onset.strength >= threshold }
        return cullByRate(
            thresholded,
            cap: Int(ceil(profile.maxNotesPerSecond))
        )
    }

    private static func percentileValue(_ values: [Float], percentile: Double) -> Float {
        guard values.count > 1 else { return values[0] }
        let position = (percentile / 100) * Double(values.count - 1)
        let lowerIndex = Int(position.rounded(.down))
        let upperIndex = min(values.count - 1, lowerIndex + 1)
        let fraction = Float(position - Double(lowerIndex))
        return values[lowerIndex] + (values[upperIndex] - values[lowerIndex]) * fraction
    }

    private static func cullByRate(
        _ onsets: [IndexedOnset],
        cap: Int
    ) -> [IndexedOnset] {
        guard cap > 0 else { return [] }
        let sorted = onsets.sorted {
            if $0.onset.time == $1.onset.time {
                return $0.index < $1.index
            }
            return $0.onset.time < $1.onset.time
        }

        var kept: [IndexedOnset] = []
        kept.reserveCapacity(sorted.count)
        for onset in sorted {
            kept.append(onset)
            let windowStart = onset.onset.time - 1
            let windowIndices = kept.indices.filter { kept[$0].onset.time > windowStart }
            if windowIndices.count > cap,
               let weakestIndex = windowIndices.min(by: { lhs, rhs in
                   if kept[lhs].onset.strength == kept[rhs].onset.strength {
                       return kept[lhs].index > kept[rhs].index
                   }
                   return kept[lhs].onset.strength < kept[rhs].onset.strength
               }) {
                kept.remove(at: weakestIndex)
            }
        }
        return kept
    }

    private static func chooseDragSources(
        from selected: [IndexedOnset],
        ratio: Double,
        rng: inout SplitMix64
    ) -> Set<Int> {
        let eligible = selected.indices.filter { index in
            guard index + 1 < selected.count else { return false }
            return selected[index + 1].onset.time - selected[index].onset.time >= 0.8
        }
        guard !eligible.isEmpty, ratio > 0 else { return [] }
        let count = min(eligible.count, max(1, Int(ceil(Double(eligible.count) * ratio))))
        return Set(shuffled(eligible, rng: &rng).prefix(count).map { selected[$0].index })
    }

    private static func chooseMovingSources(
        from sources: Set<Int>,
        ratio: Double,
        rng: inout SplitMix64
    ) -> Set<Int> {
        guard !sources.isEmpty, ratio > 0 else { return [] }
        let count = min(sources.count, max(1, Int(ceil(Double(sources.count) * ratio))))
        return Set(shuffled(Array(sources).sorted(), rng: &rng).prefix(count))
    }

    private static func shuffled<T>(_ values: [T], rng: inout SplitMix64) -> [T] {
        var result = values
        guard result.count > 1 else { return result }
        for index in stride(from: result.count - 1, through: 1, by: -1) {
            let other = rng.nextInt(upperBound: index + 1)
            result.swapAt(index, other)
        }
        return result
    }

    private static func makeGroups(
        _ selected: [IndexedOnset],
        maxSimultaneous: Int
    ) -> [[IndexedOnset]] {
        guard !selected.isEmpty else { return [] }
        let sorted = selected.sorted { $0.onset.time < $1.onset.time }
        var groups: [[IndexedOnset]] = []
        var index = 0
        while index < sorted.count {
            let start = index
            index += 1
            while index < sorted.count,
                  sorted[index].onset.time - sorted[start].onset.time <= 0.03 {
                index += 1
            }
            let group = sorted[start..<index]
                .sorted {
                    if $0.onset.strength == $1.onset.strength {
                        return $0.index < $1.index
                    }
                    return $0.onset.strength > $1.onset.strength
                }
            groups.append(Array(group.prefix(maxSimultaneous)))
        }
        return groups.sorted { $0[0].onset.time < $1[0].onset.time }
    }

    private static func nextOnset(
        after item: IndexedOnset,
        in selected: [IndexedOnset]
    ) -> IndexedOnset? {
        guard let position = selected.firstIndex(where: { $0.index == item.index }) else {
            return nil
        }
        guard position + 1 < selected.count else { return nil }
        return selected[position + 1]
    }

    private static func centroidRange(in onsets: [Onset]) -> (min: Float, max: Float) {
        guard let first = onsets.first else { return (0, 1) }
        return onsets.dropFirst().reduce(into: (min: first.centroid, max: first.centroid)) { result, onset in
            result.min = min(result.min, onset.centroid)
            result.max = max(result.max, onset.centroid)
        }
    }

    private static func quantizedLane(
        for centroid: Float,
        in range: (min: Float, max: Float)
    ) -> Int {
        guard range.max > range.min else { return 0 }
        let normalized = (centroid - range.min) / (range.max - range.min)
        return min(3, max(0, Int(floor(Double(normalized) * 4))))
    }

    private static func snappedDuration(gap: TimeInterval, tempo: Double) -> TimeInterval {
        let beat = 60 / (tempo > 0 ? tempo : 120)
        let maximum = min(gap - 0.2, 4)
        guard maximum > 0 else { return 0 }
        return floor(maximum / beat) * beat
    }

    private static func makeLanePath(
        startLane: Int,
        duration: TimeInterval,
        rng: inout SplitMix64
    ) -> [LaneKeyframe] {
        let count = rng.nextDouble() < 0.5 ? 2 : 3
        let direction: Int
        if startLane == 0 {
            direction = 1
        } else if startLane == 3 {
            direction = -1
        } else {
            direction = rng.nextDouble() < 0.5 ? -1 : 1
        }
        let targetLane = startLane + direction
        return (0..<count).map { index in
            let fraction = Double(index) / Double(count - 1)
            let lane = index == 0 ? startLane : targetLane
            return LaneKeyframe(offset: duration * fraction, lane: Double(lane))
        }
    }

    private static func removeOverlaps(from candidates: [GeneratedNote]) -> [GeneratedNote] {
        var lastEndByLane: [Int: TimeInterval] = [:]
        var result: [GeneratedNote] = []
        for candidate in candidates.sorted(by: { lhs, rhs in
            if lhs.time == rhs.time {
                return lhs.lane < rhs.lane
            }
            return lhs.time < rhs.time
        }) {
            if let previousEnd = lastEndByLane[candidate.lane], candidate.time + 1e-9 < previousEnd {
                continue
            }
            result.append(candidate)
            lastEndByLane[candidate.lane] = candidate.time
                + (candidate.kind == .drag ? candidate.duration + 0.15 : 0)
        }
        return result
    }

    private static func makePalette(from analysis: AnalysisResult) -> ThemePalette {
        let bands = [
            Band(value: Double(analysis.meanBass), hue: 0.72, order: 0),
            Band(value: Double(analysis.meanMid), hue: 0.50, order: 1),
            Band(value: Double(analysis.meanTreble), hue: 0.08, order: 2)
        ].sorted {
            if $0.value == $1.value {
                return $0.order < $1.order
            }
            return $0.value > $1.value
        }
        let dominanceTotal = bands[0].value + bands[1].value
        let hue: Double
        if dominanceTotal > 0 {
            hue = (bands[0].hue * bands[0].value + bands[1].hue * bands[1].value) / dominanceTotal
        } else {
            hue = bands[0].hue
        }

        let values = bands.map(\.value)
        let maximum = values.max() ?? 0
        let minimum = values.min() ?? 0
        let spread = maximum > 0 ? (maximum - minimum) / maximum : 0
        let saturation = 0.55 + 0.25 * min(1, max(0, spread))
        let rms = min(1, max(0, Double(analysis.meanRMS)))
        let brightness = 0.50 + 0.25 * rms
        return ThemePalette(hue: hue, saturation: saturation, brightness: brightness)
    }

    private static func makeID(seed: UInt64, index: Int) -> UUID {
        let high = splitMixValue(seed &+ UInt64(index + 1) &* 0x9E3779B97F4A7C15)
        let low = splitMixValue(high)
        return UUID(uuid: (
            UInt8(truncatingIfNeeded: high >> 56),
            UInt8(truncatingIfNeeded: high >> 48),
            UInt8(truncatingIfNeeded: high >> 40),
            UInt8(truncatingIfNeeded: high >> 32),
            UInt8(truncatingIfNeeded: high >> 24),
            UInt8(truncatingIfNeeded: high >> 16),
            UInt8(truncatingIfNeeded: high >> 8),
            UInt8(truncatingIfNeeded: high),
            UInt8(truncatingIfNeeded: low >> 56),
            UInt8(truncatingIfNeeded: low >> 48),
            UInt8(truncatingIfNeeded: low >> 40),
            UInt8(truncatingIfNeeded: low >> 32),
            UInt8(truncatingIfNeeded: low >> 24),
            UInt8(truncatingIfNeeded: low >> 16),
            UInt8(truncatingIfNeeded: low >> 8),
            UInt8(truncatingIfNeeded: low)
        ))
    }

    private static func splitMixValue(_ value: UInt64) -> UInt64 {
        var result = value &+ 0x9E3779B97F4A7C15
        result = (result ^ (result >> 30)) &* 0xBF58476D1CE4E5B9
        result = (result ^ (result >> 27)) &* 0x94D049BB133111EB
        return result ^ (result >> 31)
    }
}

private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }

    mutating func nextDouble() -> Double {
        Double(next() >> 11) * (1.0 / 9007199254740992.0)
    }

    mutating func nextInt(upperBound: Int) -> Int {
        precondition(upperBound > 0)
        return Int(next() % UInt64(upperBound))
    }
}
