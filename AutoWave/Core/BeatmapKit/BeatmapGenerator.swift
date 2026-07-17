import Foundation

enum BeatmapGenerator {
    static let version = 3

    static func generate(from analysis: AnalysisResult, difficulty: Difficulty, seed: UInt64) -> Beatmap {
        let profile = DifficultyProfile.profile(for: difficulty)
        let beat = beatDuration(for: analysis.tempo)
        let subdivision = gridSubdivision(for: difficulty, beat: beat)
        var rng = SplitMix64(seed: seed)
        let indexedOnsets = analysis.onsets.enumerated().map {
            IndexedOnset(index: $0.offset, onset: $0.element)
        }
        let selected = selectOnsets(indexedOnsets, profile: profile)
        let dragSources = chooseDragSources(
            from: selected,
            ratio: profile.dragRatio,
            beat: beat,
            meanBass: analysis.meanBass,
            rng: &rng
        )
        let movingSources = chooseMovingSources(
            from: dragSources,
            ratio: profile.movingDragRatio,
            rng: &rng
        )
        let patternEvents = cullByRate(
            makePatternEvents(
                from: selected,
                difficulty: difficulty,
                beat: beat,
                subdivision: subdivision,
                duration: analysis.duration,
                rng: &rng
            ),
            cap: Int(ceil(profile.maxNotesPerSecond))
        )
        let centroidValues = analysis.onsets.map(\.centroid).sorted()
        let groups = makeGroups(patternEvents, maxSimultaneous: profile.maxSimultaneous)

        var candidates: [GeneratedNote] = []
        candidates.reserveCapacity(patternEvents.count)
        var previousLane: Int?
        for group in groups {
            var lanes: [Int] = []
            for event in group {
                let lane = assignLane(
                    for: event.source.onset,
                    centroidValues: centroidValues,
                    laneCount: profile.laneCount,
                    difficulty: difficulty,
                    previousLane: previousLane,
                    occupiedLanes: lanes,
                    rng: &rng
                )
                lanes.append(lane)
                previousLane = lane

                let isDrag = event.isPrimary && dragSources.contains(event.source.index)
                let duration: TimeInterval
                if isDrag, let next = nextOnset(after: event.source, in: selected) {
                    duration = snappedDuration(
                        gap: next.onset.time - event.source.onset.time,
                        beat: beat,
                        subdivision: subdivision
                    )
                } else {
                    duration = 0
                }

                let path: [LaneKeyframe]
                if duration > 0, movingSources.contains(event.source.index) {
                    path = makeLanePath(
                        startLane: lane,
                        duration: duration,
                        laneCount: profile.laneCount,
                        difficulty: difficulty,
                        rng: &rng
                    )
                } else {
                    path = []
                }

                candidates.append(
                    GeneratedNote(
                        kind: duration > 0 ? .drag : .tap,
                        time: event.time,
                        lane: lane,
                        duration: duration,
                        lanePath: path
                    )
                )
            }
        }

        let notes = removeDragSpanConflicts(
            from: removeOverlaps(from: candidates)
        ).enumerated().map { index, candidate in
            Note(
                id: makeID(seed: seed, index: index),
                kind: candidate.kind,
                time: candidate.time,
                lane: Double(candidate.lane),
                duration: candidate.duration,
                lanePath: candidate.lanePath
            )
        }

        let theme = GameTheme.select(
            tempo: analysis.tempo,
            meanBass: analysis.meanBass,
            meanMid: analysis.meanMid,
            meanTreble: analysis.meanTreble,
            meanRMS: analysis.meanRMS
        )

        return Beatmap(
            difficulty: difficulty,
            tempo: analysis.tempo,
            notes: notes,
            palette: theme.themePalette,
            generatorVersion: version,
            themeID: theme.id,
            laneCount: profile.laneCount
        )
    }

    private struct IndexedOnset {
        var index: Int
        var onset: Onset
    }

    private struct PatternEvent {
        var identity: Int
        var source: IndexedOnset
        var time: TimeInterval
        var isPrimary: Bool
        var isChord: Bool

        var priority: Float {
            source.onset.strength + (isChord ? 0.02 : 0)
        }
    }

    private struct GeneratedNote {
        var kind: NoteKind
        var time: TimeInterval
        var lane: Int
        var duration: TimeInterval
        var lanePath: [LaneKeyframe]
    }

    private static func selectOnsets(
        _ onsets: [IndexedOnset],
        profile: DifficultyProfile
    ) -> [IndexedOnset] {
        guard !onsets.isEmpty else { return [] }
        let strengths = onsets.map { $0.onset.strength }.sorted()
        let threshold = percentileValue(strengths, percentile: profile.strengthPercentile)
        return onsets
            .filter { $0.onset.strength >= threshold && $0.onset.time >= 0 }
            .sorted {
                if $0.onset.time == $1.onset.time {
                    return $0.index < $1.index
                }
                return $0.onset.time < $1.onset.time
            }
    }

    private static func percentileValue(_ values: [Float], percentile: Double) -> Float {
        guard values.count > 1 else { return values[0] }
        let position = (percentile / 100) * Double(values.count - 1)
        let lowerIndex = Int(position.rounded(.down))
        let upperIndex = min(values.count - 1, lowerIndex + 1)
        let fraction = Float(position - Double(lowerIndex))
        return values[lowerIndex] + (values[upperIndex] - values[lowerIndex]) * fraction
    }

    private static func makePatternEvents(
        from selected: [IndexedOnset],
        difficulty: Difficulty,
        beat: TimeInterval,
        subdivision: TimeInterval,
        duration: TimeInterval,
        rng: inout SplitMix64
    ) -> [PatternEvent] {
        guard !selected.isEmpty, duration > 0 else { return [] }

        var events = selected.map { item in
            PatternEvent(
                identity: item.index,
                source: item,
                time: snappedTime(item.onset.time, subdivision: subdivision, duration: duration),
                isPrimary: true,
                isChord: false
            )
        }

        guard difficulty != .heaven, difficulty != .easy, selected.count > 1 else {
            return events.sorted(by: patternEventSort)
        }

        let activeWindow: TimeInterval = switch difficulty {
        case .normal:
            beat * 1.5
        case .hard:
            beat * 2
        case .hell:
            beat * 2.5
        case .heaven, .easy:
            0
        }
        let primaryGridIndices = Set(events.map { gridIndex(for: $0.time, subdivision: subdivision) })
        var occupiedGridIndices = primaryGridIndices
        let firstGridIndex = gridIndex(for: events.map(\.time).min()!, subdivision: subdivision)
        let lastGridIndex = gridIndex(for: events.map(\.time).max()!, subdivision: subdivision)
        var nextIdentity = selected.map(\.index).max() ?? 0

        if firstGridIndex <= lastGridIndex {
            for index in firstGridIndex...lastGridIndex where !occupiedGridIndices.contains(index) {
                let time = Double(index) * subdivision
                guard let source = selected.min(by: { lhs, rhs in
                    let leftDistance = abs(lhs.onset.time - time)
                    let rightDistance = abs(rhs.onset.time - time)
                    if leftDistance == rightDistance {
                        return lhs.index < rhs.index
                    }
                    return leftDistance < rightDistance
                }), abs(source.onset.time - time) <= activeWindow else {
                    continue
                }

                nextIdentity += 1
                events.append(
                    PatternEvent(
                        identity: nextIdentity,
                        source: source,
                        time: time,
                        isPrimary: false,
                        isChord: false
                    )
                )
                occupiedGridIndices.insert(index)
            }
        }

        if difficulty == .hell {
            let primaryEvents = events.filter(\.isPrimary)
            for event in primaryEvents where event.source.onset.strength >= 0.35 {
                guard rng.nextDouble() < 0.45 else { continue }
                nextIdentity += 1
                events.append(
                    PatternEvent(
                        identity: nextIdentity,
                        source: event.source,
                        time: event.time,
                        isPrimary: false,
                        isChord: true
                    )
                )
            }
        }

        return events.sorted(by: patternEventSort)
    }

    private static func cullByRate(
        _ events: [PatternEvent],
        cap: Int
    ) -> [PatternEvent] {
        guard cap > 0 else { return [] }
        let sorted = events.sorted(by: patternEventSort)
        var active: [PatternEvent] = []
        var result: [PatternEvent] = []
        result.reserveCapacity(sorted.count)

        var index = 0
        while index < sorted.count {
            let start = index
            index += 1
            while index < sorted.count, sorted[index].time == sorted[start].time {
                index += 1
            }

            let group = Array(sorted[start..<index])
            let windowStart = group[0].time - 1
            active.removeAll { $0.time <= windowStart }
            let chordPair = group.filter { !$0.isChord }.prefix(1)
                + group.filter(\.isChord).prefix(1)
            let toKeep = chordPair.count == 2 ? Array(chordPair) : Array(group.prefix(1))
            var available = cap - active.count

            if toKeep.count > available, chordPair.count == 2 {
                let removable = active
                    .filter { !$0.isChord }
                    .sorted { $0.time < $1.time }
                    + active.filter(\.isChord)
                let removeCount = toKeep.count - available
                guard removeCount <= removable.count else { continue }
                for removed in removable.prefix(removeCount) {
                    active.removeAll { $0.identity == removed.identity }
                    result.removeAll { $0.identity == removed.identity }
                }
                available += removeCount
            }

            guard toKeep.count <= available else { continue }
            active.append(contentsOf: toKeep)
            result.append(contentsOf: toKeep)
        }

        return result.sorted(by: patternEventSort)
    }

    private static func patternEventSort(_ lhs: PatternEvent, _ rhs: PatternEvent) -> Bool {
        if lhs.time == rhs.time {
            if lhs.isChord != rhs.isChord {
                return !lhs.isChord
            }
            return lhs.identity < rhs.identity
        }
        return lhs.time < rhs.time
    }

    private static func chooseDragSources(
        from selected: [IndexedOnset],
        ratio: Double,
        beat: TimeInterval,
        meanBass: Float,
        rng: inout SplitMix64
    ) -> Set<Int> {
        let gaps = selected.indices.filter { index in
            guard index + 1 < selected.count else { return false }
            return selected[index + 1].onset.time - selected[index].onset.time >= beat
        }
        let bassEligible = gaps.filter { index in
            let nextBass = selected[index + 1].onset.bass
            let bassThreshold = max(0.0001, meanBass * 0.75)
            return max(selected[index].onset.bass, nextBass) >= bassThreshold
        }
        let eligible = bassEligible.isEmpty ? gaps : bassEligible
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
        _ events: [PatternEvent],
        maxSimultaneous: Int
    ) -> [[PatternEvent]] {
        guard !events.isEmpty else { return [] }
        let sorted = events.sorted(by: patternEventSort)
        var groups: [[PatternEvent]] = []
        var index = 0
        while index < sorted.count {
            let start = index
            index += 1
            while index < sorted.count, abs(sorted[index].time - sorted[start].time) <= 1e-9 {
                index += 1
            }
            let group = sorted[start..<index]
                .sorted {
                    if $0.priority == $1.priority {
                        return $0.identity < $1.identity
                    }
                    return $0.priority > $1.priority
                }
            groups.append(Array(group.prefix(maxSimultaneous)))
        }
        return groups
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

    private static func assignLane(
        for onset: Onset,
        centroidValues: [Float],
        laneCount: Int,
        difficulty: Difficulty,
        previousLane: Int?,
        occupiedLanes: [Int],
        rng: inout SplitMix64
    ) -> Int {
        let centroidPercentile = percentileRank(of: onset.centroid, in: centroidValues)
        let bandTotal = max(0.0001, onset.bass + onset.mid + onset.treble)
        let trebleBalance = Double(onset.treble / bandTotal)
        let musicalPosition = min(1, max(0, centroidPercentile * 0.75 + trebleBalance * 0.25))
        let baseLane = min(laneCount - 1, max(0, Int(floor(musicalPosition * Double(laneCount)))))
        var lane = baseLane

        let variation = rng.nextDouble()
        let variationDirection = rng.nextDouble() < 0.5 ? -1 : 1
        if previousLane == baseLane, variation < 0.6 {
            lane = baseLane + variationDirection
        } else if variation < 0.2 {
            lane = baseLane + variationDirection
        } else if (difficulty == .hard || difficulty == .hell), variation > 0.82 {
            lane = baseLane + variationDirection * 2
        }
        lane = min(laneCount - 1, max(0, lane))

        if occupiedLanes.contains(lane) {
            let alternatives = [1, -1, 2, -2].map { lane + $0 }
            lane = alternatives.first(where: {
                $0 >= 0 && $0 < laneCount && !occupiedLanes.contains($0)
            }) ?? lane
        }
        return lane
    }

    private static func percentileRank(of value: Float, in sortedValues: [Float]) -> Double {
        guard let first = sortedValues.first, let last = sortedValues.last else { return 0.5 }
        guard last > first else { return 0.5 }
        let lowerCount = sortedValues.firstIndex(where: { $0 >= value }) ?? sortedValues.count
        return Double(lowerCount) / Double(sortedValues.count - 1)
    }

    private static func snappedDuration(
        gap: TimeInterval,
        beat: TimeInterval,
        subdivision: TimeInterval
    ) -> TimeInterval {
        let maximum = min(gap - beat * 0.25, 4)
        guard maximum >= subdivision else { return 0 }
        return floor(maximum / subdivision) * subdivision
    }

    private static func makeLanePath(
        startLane: Int,
        duration: TimeInterval,
        laneCount: Int,
        difficulty: Difficulty,
        rng: inout SplitMix64
    ) -> [LaneKeyframe] {
        let count = 2 + rng.nextInt(upperBound: 3)
        let maximumDistance = min(3, laneCount - 1)
        let minimumDistance = difficulty == .hell ? min(2, maximumDistance) : 1
        let distance = minimumDistance + rng.nextInt(upperBound: maximumDistance - minimumDistance + 1)
        let direction: Int
        if startLane < distance {
            direction = 1
        } else if startLane + distance >= laneCount {
            direction = -1
        } else {
            direction = rng.nextDouble() < 0.5 ? -1 : 1
        }
        let targetLane = min(laneCount - 1, max(0, startLane + direction * distance))

        return (0..<count).map { index in
            let fraction = Double(index) / Double(count - 1)
            let lane = Double(startLane) + Double(targetLane - startLane) * fraction
            return LaneKeyframe(offset: duration * fraction, lane: lane.rounded())
        }
    }

    private static func removeOverlaps(from candidates: [GeneratedNote]) -> [GeneratedNote] {
        var lastEndByLane: [Int: TimeInterval] = [:]
        var result: [GeneratedNote] = []
        for candidate in candidates.sorted(by: generatedNoteSort) {
            if let previousEnd = lastEndByLane[candidate.lane], candidate.time + 1e-9 < previousEnd {
                continue
            }
            result.append(candidate)
            lastEndByLane[candidate.lane] = candidate.time
                + (candidate.kind == .drag ? candidate.duration + 0.15 : 0)
        }
        return result
    }

    private static func removeDragSpanConflicts(from candidates: [GeneratedNote]) -> [GeneratedNote] {
        let drags = candidates.filter { $0.kind == .drag }
        return candidates.filter { candidate in
            guard candidate.kind == .tap else { return true }
            return !drags.contains { drag in
                let dragLanes = [drag.lane] + drag.lanePath.map { Int($0.lane.rounded()) }
                let minimumLane = dragLanes.min()!
                let maximumLane = dragLanes.max()!
                let dragEnd = drag.time + drag.duration
                let isActive = candidate.time >= drag.time - 1e-9
                    && candidate.time <= dragEnd + 1e-9
                return isActive && candidate.lane >= minimumLane && candidate.lane <= maximumLane
            }
        }
    }

    private static func generatedNoteSort(_ lhs: GeneratedNote, _ rhs: GeneratedNote) -> Bool {
        if lhs.time == rhs.time {
            if lhs.lane == rhs.lane {
                return lhs.kind == .drag
            }
            return lhs.lane < rhs.lane
        }
        return lhs.time < rhs.time
    }

    private static func beatDuration(for tempo: Double) -> TimeInterval {
        60 / (tempo > 0 ? tempo : 120)
    }

    private static func gridSubdivision(for difficulty: Difficulty, beat: TimeInterval) -> TimeInterval {
        switch difficulty {
        case .heaven, .easy:
            beat / 2
        case .normal:
            beat / 4
        case .hard, .hell:
            beat / 8
        }
    }

    private static func snappedTime(
        _ time: TimeInterval,
        subdivision: TimeInterval,
        duration: TimeInterval
    ) -> TimeInterval {
        min(duration, max(0, Double(Int(round(time / subdivision))) * subdivision))
    }

    private static func gridIndex(for time: TimeInterval, subdivision: TimeInterval) -> Int {
        Int(round(time / subdivision))
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
