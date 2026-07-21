import Foundation

enum BeatmapGenerator {
    static let version = 9
    static let minimumPlayableNoteTime: TimeInterval = 2
    private static let dragSpanPadding: TimeInterval = 0.08
    private static let minimumLaneStepInterval: TimeInterval = 0.35

    // Tunables ported from tools/notegen-playground.html (playground parity).
    struct GenerationTuning: Sendable, Equatable {
        var laneMappingWeights: [MusicalRole: Double]
        var antiRepeatStrength: Double
        var dragMinDuration: TimeInterval
        var dragMaxDuration: TimeInterval

        static let `default` = GenerationTuning(
            laneMappingWeights: [.drum: 0, .bass: -0.25, .melody: 0.2, .vocal: 0.15, .accompaniment: 0.05],
            antiRepeatStrength: 1,
            dragMinDuration: 0.125,
            dragMaxDuration: 4
        )
    }

    static func generate(
        from analysis: AnalysisResult,
        difficulty: Difficulty,
        seed: UInt64,
        laneCountOverride: Int? = nil,
        tuning: GenerationTuning = .default
    ) -> Beatmap {
        let profile = DifficultyProfile.profile(for: difficulty)
        let laneCount = min(max(laneCountOverride ?? profile.laneCount, 4), 7)
        let beat = beatDuration(for: analysis.tempo)
        let subdivision = gridSubdivision(
            for: difficulty,
            beat: beat,
            configuration: analysis.configuration
        )
        let policy = analysis.configuration.policy(for: difficulty)
        let npsCap = Int(ceil(policy.npsCap))
        var rng = SplitMix64(seed: seed)
        let indexedOnsets = analysis.onsets.enumerated().map {
            IndexedOnset(index: $0.offset, onset: $0.element)
        }
        let musicalEvents = MusicalEventAdapter.events(
            from: analysis,
            difficulty: difficulty,
            configuration: analysis.configuration
        ).map(scheduleMIREvent)
        let usesMIR = !musicalEvents.isEmpty
        let selected: [IndexedOnset]
        var patternEvents: [PatternEvent]
        if usesMIR {
            selected = []
            patternEvents = enforceMinimumSequentialGap(
                cullByRate(
                    makeMIRPatternEvents(
                        musicalEvents,
                        subdivision: subdivision,
                        duration: analysis.duration,
                        phase: beatGridPhase(from: analysis.beatGrid, subdivision: subdivision),
                        snapTolerance: analysis.configuration.beatSnapTolerance
                    ),
                    cap: npsCap,
                    maxSimultaneous: policy.maxSimultaneous
                ),
                gap: policy.minimumSequentialGap
            )
        } else {
            let detectedOnsets = selectOnsets(indexedOnsets, profile: profile, analysis: analysis)
            let onsetRate = analysis.duration > 0
                ? Double(detectedOnsets.count) / analysis.duration
                : 0
            selected = detectedOnsets.isEmpty || (onsetRate < 0.5 && analysis.duration >= 30)
                ? fallbackBeatOnsets(for: analysis)
                : detectedOnsets
            patternEvents = enforceMinimumSequentialGap(
                cullByRate(
                    makePatternEvents(
                        from: selected,
                        difficulty: difficulty,
                        subdivision: subdivision,
                        duration: analysis.duration,
                        beatPhase: beatGridPhase(from: selected, subdivision: subdivision),
                        snapTolerance: analysis.configuration.beatSnapTolerance,
                        rng: &rng
                    ),
                    cap: npsCap,
                    maxSimultaneous: policy.maxSimultaneous
                ),
                gap: policy.minimumSequentialGap
            )
        }
        var sustainByObjectID: [Int: SustainCandidate] = [:]
        let dragSources: Set<Int>
        if usesMIR {
            var eligibleByObjectID: [Int: SustainCandidate] = [:]
            for candidate in analysis.sustainCandidates where
                candidate.sourceRole != .drum
                    && candidate.duration >= policy.minimumSustainDuration
                    && candidate.confidence >= policy.minimumConfidence {
                if let existing = eligibleByObjectID[candidate.objectID] {
                    eligibleByObjectID[candidate.objectID] = SustainCandidate.preferred(candidate, over: existing)
                } else {
                    eligibleByObjectID[candidate.objectID] = candidate
                }
            }
            let eligible = eligibleByObjectID.values.compactMap(playableSustainCandidate).sorted {
                if $0.sustainScore == $1.sustainScore { return $0.objectID < $1.objectID }
                return $0.sustainScore > $1.sustainScore
            }
            let count = profile.dragRatio > 0
                ? min(eligible.count, max(1, Int(ceil(Double(eligible.count) * profile.dragRatio))))
                : 0
            let chosen = eligible.prefix(count)
            for candidate in chosen {
                sustainByObjectID[candidate.objectID] = candidate
            }
            dragSources = Set(chosen.map(\.objectID))
            patternEvents = insertMIRDragHeads(
                into: patternEvents,
                candidates: Array(chosen),
                preferredSourceObjectIDs: dragSources,
                subdivision: subdivision,
                duration: analysis.duration,
                phase: beatGridPhase(from: analysis.beatGrid, subdivision: subdivision),
                snapTolerance: analysis.configuration.beatSnapTolerance,
                npsCap: npsCap,
                maxSimultaneous: policy.maxSimultaneous
            )
        } else {
            let survivingSources = selected.filter { item in
                patternEvents.contains { event in
                    event.isPrimary && event.source.index == item.index
                }
            }
            dragSources = chooseDragSources(
                from: survivingSources,
                ratio: profile.dragRatio,
                beat: beat,
                meanBass: analysis.meanBass,
                rng: &rng
            )
        }
        let movingSources = usesMIR
            ? Set<Int>()
            : chooseMovingSources(from: dragSources, ratio: profile.movingDragRatio, rng: &rng)
        let centroidValues = analysis.onsets.map(\.centroid).sorted()
        let groups = makeGroups(
            patternEvents,
            maxSimultaneous: profile.maxSimultaneous,
            preferredSourceObjectIDs: usesMIR ? dragSources : []
        )

        var candidates: [GeneratedNote] = []
        candidates.reserveCapacity(patternEvents.count)
        var previousLane: Int?
        var laneHistory: [Int] = []
        for group in groups {
            var lanes: [Int] = []
            for event in group {
                let lane = assignLane(
                    for: event.source.onset,
                    role: event.sourceRole,
                    centroidValues: centroidValues,
                    laneCount: laneCount,
                    previousLane: previousLane,
                    occupiedLanes: lanes,
                    recentLanes: laneHistory,
                    tuning: tuning,
                    rng: &rng
                )
                lanes.append(lane)
                previousLane = lane
                laneHistory.append(lane)
                if laneHistory.count > 8 {
                    laneHistory.removeFirst()
                }

                let sourceID = event.sourceObjectID ?? event.source.index
                let isDrag = event.isPrimary && dragSources.contains(sourceID)
                let duration: TimeInterval
                if isDrag, let candidate = sustainByObjectID[sourceID] {
                    duration = snappedSustainDuration(
                        candidate: candidate,
                        beat: beat,
                        subdivision: subdivision,
                        tuning: tuning
                    )
                } else if isDrag, let next = nextOnset(after: event.source, in: selected) {
                    duration = snappedDuration(
                        gap: next.onset.time - event.source.onset.time,
                        beat: beat,
                        subdivision: subdivision,
                        tuning: tuning
                    )
                } else {
                    duration = 0
                }

                let path: [LaneKeyframe]
                if duration > 0, let candidate = sustainByObjectID[sourceID] {
                    path = makeContourLanePath(
                        candidate: candidate,
                        startLane: lane,
                        duration: duration,
                        laneCount: laneCount
                    )
                } else if duration > 0, movingSources.contains(event.source.index) {
                    path = makeLanePath(
                        startLane: lane,
                        duration: duration,
                        laneCount: laneCount,
                        difficulty: difficulty,
                        rng: &rng
                    )
                } else {
                    path = []
                }

                candidates.append(
                    GeneratedNote(
                        identity: event.identity,
                        kind: duration > 0 ? .drag : .tap,
                        time: event.time,
                        lane: lane,
                        duration: duration,
                        lanePath: path,
                        sourceRole: event.sourceRole
                    )
                )
            }
        }

        let placedCandidates = enforcePlacementLimits(
            from: removeOverlaps(from: candidates),
            maxSimultaneous: profile.maxSimultaneous,
            rng: &rng
        )
        let minimumLaneGap = difficulty == .heaven || difficulty == .easy ? 0.25 : 0.12
        let notes = enforceSameLaneGap(
            from: removeDragSpanConflicts(
                from: placedCandidates,
                laneCount: laneCount,
                maxSimultaneous: profile.maxSimultaneous,
                minimumGap: minimumLaneGap
            ),
            minimumGap: minimumLaneGap
        )
            .filter { $0.time >= minimumPlayableNoteTime }
            .enumerated().map { index, candidate in
            Note(
                id: makeID(seed: seed, index: index),
                kind: candidate.kind,
                time: candidate.time,
                lane: Double(candidate.lane),
                duration: candidate.duration,
                lanePath: candidate.lanePath,
                sourceRole: candidate.sourceRole
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
            laneCount: laneCount
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
        var band: OnsetBand
        var sourceRole: MusicalRole = .accompaniment
        var sourceObjectID: Int? = nil
        var sustainCandidate: SustainCandidate? = nil

        var priority: Float {
            source.onset.strength + (isChord ? 0.02 : 0)
        }
    }

    private struct GeneratedNote {
        var identity: Int
        var kind: NoteKind
        var time: TimeInterval
        var lane: Int
        var duration: TimeInterval
        var lanePath: [LaneKeyframe]
        var sourceRole: MusicalRole? = nil
    }

    private static func selectOnsets(
        _ onsets: [IndexedOnset],
        profile: DifficultyProfile,
        analysis: AnalysisResult
    ) -> [IndexedOnset] {
        let playableOnsets = onsets.filter {
            $0.onset.time >= minimumPlayableNoteTime
        }
        guard !playableOnsets.isEmpty else { return [] }
        let grouped = Dictionary(grouping: playableOnsets) {
            Int($0.onset.time.rounded(.down))
        }
        return grouped.keys.sorted().flatMap { second in
            let window = grouped[second] ?? []
            let intensity = intensity(at: Double(second) + 0.5, curve: analysis.intensityCurve)
            let percentile = profile.strengthPercentile + (1 - intensity) * 20
            let threshold = percentileValue(
                window.map { $0.onset.strength }.sorted(),
                percentile: percentile
            )
            let densityScale = 0.35 + intensity * 0.65
            let capacity = max(1, Int(ceil(profile.maxNotesPerSecond * densityScale)))
            let ranked = window.sorted {
                if $0.onset.strength == $1.onset.strength {
                    return $0.onset.time < $1.onset.time
                }
                return $0.onset.strength > $1.onset.strength
            }
            let thresholdQualified = ranked.filter { $0.onset.strength >= threshold }
            let budgetFill = ranked.filter { $0.onset.strength < threshold }
            return Array((thresholdQualified + budgetFill).prefix(capacity))
        }
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
        subdivision: TimeInterval,
        duration: TimeInterval,
        beatPhase: TimeInterval,
        snapTolerance: TimeInterval,
        rng: inout SplitMix64
    ) -> [PatternEvent] {
        guard !selected.isEmpty, duration > 0 else { return [] }

        var events = selected.map { item in
            PatternEvent(
                identity: item.index,
                source: item,
                time: snappedTime(
                    item.onset.time,
                    subdivision: subdivision,
                    duration: duration,
                    phase: beatPhase,
                    tolerance: snapTolerance
                ),
                isPrimary: true,
                isChord: false,
                band: item.onset.band,
                sourceRole: role(for: item.onset.band)
            )
        }

        guard difficulty != .heaven, difficulty != .easy, selected.count > 1 else {
            return events.sorted(by: patternEventSort)
        }

        var nextIdentity = selected.map(\.index).max() ?? 0
        let streamBeat = difficulty == .normal ? subdivision * 4 : subdivision * 8
        let streamSubdivision: TimeInterval?
        switch difficulty {
        case .normal:
            streamSubdivision = subdivision
        case .hard, .hell:
            streamSubdivision = subdivision
        case .heaven, .easy:
            streamSubdivision = nil
        }

        if let streamSubdivision {
            let primaryEvents = events
            for event in primaryEvents where event.band == .high {
                var streamTime = event.time + streamSubdivision
                let nextTime = selected.first {
                    $0.onset.time > event.source.onset.time + 1e-9
                }?.onset.time ?? duration
                while streamTime < min(nextTime, event.time + streamBeat) {
                    guard streamTime <= duration else { break }
                    nextIdentity += 1
                    events.append(
                        PatternEvent(
                            identity: nextIdentity,
                            source: event.source,
                            time: streamTime,
                            isPrimary: false,
                            isChord: false,
                            band: .high
                        )
                    )
                    streamTime += streamSubdivision
                }
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
                        isChord: true,
                        band: .low
                    )
                )
                guard rng.nextDouble() < 0.35 else { continue }
                nextIdentity += 1
                events.append(
                    PatternEvent(
                        identity: nextIdentity,
                        source: event.source,
                        time: event.time,
                        isPrimary: false,
                        isChord: true,
                        band: .low
                    )
                )
            }
        } else if difficulty == .hard {
            let primaryEvents = events.filter(\.isPrimary)
            for event in primaryEvents
                where event.band == .low && event.source.onset.strength >= 0.55 {
                guard rng.nextDouble() < 0.3 else { continue }
                nextIdentity += 1
                events.append(
                    PatternEvent(
                        identity: nextIdentity,
                        source: event.source,
                        time: event.time,
                        isPrimary: false,
                        isChord: true,
                        band: .low
                    )
                )
            }
        }

        return events.sorted(by: patternEventSort)
    }

    private static func makeMIRPatternEvents(
        _ events: [MusicalEvent],
        subdivision: TimeInterval,
        duration: TimeInterval,
        phase: TimeInterval,
        snapTolerance: TimeInterval
    ) -> [PatternEvent] {
        events.map { event in
            let onset = Onset(
                time: event.time,
                strength: event.importance,
                bass: event.sourceRole == .bass ? 1 : 0.2,
                mid: event.sourceRole == .melody || event.sourceRole == .vocal ? 1 : 0.2,
                treble: event.sourceRole == .accompaniment ? 1 : 0.2,
                centroid: event.sustainCandidate?.centroidContour.first?.value ?? 440,
                band: band(for: event.sourceRole)
            )
            return PatternEvent(
                identity: event.id,
                source: IndexedOnset(index: event.id, onset: onset),
                time: snappedTime(
                    event.time,
                    subdivision: subdivision,
                    duration: duration,
                    phase: phase,
                    tolerance: snapTolerance
                ),
                isPrimary: true,
                isChord: false,
                band: band(for: event.sourceRole),
                sourceRole: event.sourceRole,
                sourceObjectID: event.sourceObjectID,
                sustainCandidate: event.sustainCandidate
            )
        }
        .sorted(by: patternEventSort)
    }

    private static func insertMIRDragHeads(
        into events: [PatternEvent],
        candidates: [SustainCandidate],
        preferredSourceObjectIDs: Set<Int>,
        subdivision: TimeInterval,
        duration: TimeInterval,
        phase: TimeInterval,
        snapTolerance: TimeInterval,
        npsCap: Int,
        maxSimultaneous: Int
    ) -> [PatternEvent] {
        var result = events
        for candidate in candidates {
            let snappedOnset = snappedTime(
                candidate.onsetTime,
                subdivision: subdivision,
                duration: duration,
                phase: phase,
                tolerance: snapTolerance
            )
            guard !result.contains(where: {
                $0.sourceObjectID == candidate.objectID
                    && abs($0.time - snappedOnset) <= 1e-9
            }) else {
                continue
            }

            let onset = Onset(
                time: candidate.onsetTime,
                strength: candidate.importanceScore,
                bass: candidate.sourceRole == .bass ? 1 : 0.2,
                mid: candidate.sourceRole == .melody || candidate.sourceRole == .vocal ? 1 : 0.2,
                treble: candidate.sourceRole == .accompaniment ? 1 : 0.2,
                centroid: candidate.centroidContour.first?.value ?? 440,
                band: band(for: candidate.sourceRole)
            )
            result.append(
                PatternEvent(
                    identity: candidate.objectID,
                    source: IndexedOnset(index: candidate.objectID, onset: onset),
                    time: snappedOnset,
                    isPrimary: true,
                    isChord: false,
                    band: band(for: candidate.sourceRole),
                    sourceRole: candidate.sourceRole,
                    sourceObjectID: candidate.objectID,
                    sustainCandidate: candidate
                )
            )
        }

        return cullByRate(
            result,
            cap: npsCap,
            maxSimultaneous: maxSimultaneous,
            preferredSourceObjectIDs: preferredSourceObjectIDs
        )
    }

    private static func role(for band: OnsetBand) -> MusicalRole {
        switch band {
        case .low: .bass
        case .mid: .accompaniment
        case .high: .melody
        }
    }

    private static func band(for role: MusicalRole) -> OnsetBand {
        switch role {
        case .drum, .bass: .low
        case .melody, .vocal: .mid
        case .accompaniment: .high
        }
    }

    private static func fallbackBeatOnsets(for analysis: AnalysisResult) -> [IndexedOnset] {
        guard analysis.duration >= minimumPlayableNoteTime else {
            return []
        }

        let beat = beatDuration(for: analysis.tempo)
        let firstBeat = ceil(minimumPlayableNoteTime / beat) * beat
        guard firstBeat <= analysis.duration else { return [] }

        var result: [IndexedOnset] = []
        var time = firstBeat
        var index = -1
        while time <= analysis.duration + 1e-9 {
            result.append(
                IndexedOnset(
                    index: index,
                    onset: Onset(
                        time: time,
                        strength: max(0.05, Float(intensity(at: time, curve: analysis.intensityCurve))),
                        bass: analysis.meanBass,
                        mid: analysis.meanMid,
                        treble: analysis.meanTreble,
                        centroid: 0
                    )
                )
            )
            time += beat
            index -= 1
        }
        return result
    }

    private static func intensity(at time: TimeInterval, curve: [Float]) -> Double {
        guard !curve.isEmpty else { return 1 }
        let index = min(curve.count - 1, max(0, Int(time.rounded(.down))))
        return Double(min(1, max(0, curve[index])))
    }

    private static func beatGridPhase(
        from onsets: [IndexedOnset],
        subdivision: TimeInterval
    ) -> TimeInterval {
        guard subdivision > 0, !onsets.isEmpty else { return 0 }

        let resolution = 32
        var bestPhase = 0.0
        var bestScore = -Double.infinity
        for step in 0..<resolution {
            let phase = subdivision * Double(step) / Double(resolution)
            let score = onsets.reduce(0.0) { total, item in
                let nearestGrid = phase
                    + ((item.onset.time - phase) / subdivision).rounded() * subdivision
                let distance = abs(item.onset.time - nearestGrid)
                let confidence = max(0, 1 - distance / (subdivision * 0.5))
                return total + Double(item.onset.strength) * confidence
            }
            if score > bestScore {
                bestScore = score
                bestPhase = phase
            }
        }
        return bestPhase
    }

    private static func beatGridPhase(
        from beatGrid: BeatGrid,
        subdivision: TimeInterval
    ) -> TimeInterval {
        guard subdivision > 0, let firstBeat = beatGrid.beats.first?.time else { return 0 }
        return firstBeat - (firstBeat / subdivision).rounded(.down) * subdivision
    }

    private static func enforceMinimumSequentialGap(
        _ events: [PatternEvent],
        gap: TimeInterval
    ) -> [PatternEvent] {
        let sorted = events.sorted(by: patternEventSort)
        var result: [PatternEvent] = []
        var index = 0
        var lastTime: TimeInterval?

        while index < sorted.count {
            let start = index
            index += 1
            while index < sorted.count, abs(sorted[index].time - sorted[start].time) <= 1e-9 {
                index += 1
            }

            // Events within this group share the same timestamp (e.g. a chord pair)
            // and are exempt from the gap check between each other; only the gap
            // between distinct timestamps is enforced below.
            let group = Array(sorted[start..<index])
            if let lastTime, group[0].time - lastTime < gap - 1e-9 {
                continue
            }
            result.append(contentsOf: group)
            lastTime = group[0].time
        }

        return result
    }

    private static func cullByRate(
        _ events: [PatternEvent],
        cap: Int,
        maxSimultaneous: Int = 1,
        preferredSourceObjectIDs: Set<Int> = []
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

            // Rank the timestamp group by preferred source first, then by highest
            // importance/strength (chords get a small bonus via `priority`), so the
            // strongest simultaneous events are the ones kept.
            let group = Array(sorted[start..<index]).sorted {
                let lhsPreferred = $0.sourceObjectID.map(preferredSourceObjectIDs.contains) ?? false
                let rhsPreferred = $1.sourceObjectID.map(preferredSourceObjectIDs.contains) ?? false
                if lhsPreferred != rhsPreferred { return lhsPreferred }
                if $0.priority != $1.priority { return $0.priority > $1.priority }
                return $0.identity < $1.identity
            }
            let windowStart = group[0].time - 1
            active.removeAll { $0.time <= windowStart }

            // Keep up to `maxSimultaneous` events per timestamp (difficulties whose
            // policy allows only 1 simply keep the single strongest event); the
            // extra kept events still count toward the nps cap below.
            let keepCount = max(1, min(maxSimultaneous, group.count))
            let toKeep = Array(group.prefix(keepCount))
            var available = cap - active.count

            if toKeep.count > available {
                let needed = toKeep.count - available
                let hasPreferred = toKeep.contains {
                    $0.sourceObjectID.map(preferredSourceObjectIDs.contains) ?? false
                }
                if hasPreferred || keepCount > 1 {
                    let removable = active
                        .filter { !($0.sourceObjectID.map(preferredSourceObjectIDs.contains) ?? false) }
                        .sorted {
                            if $0.time == $1.time { return $0.identity < $1.identity }
                            return $0.time < $1.time
                        }
                    if removable.count >= needed {
                        for removed in removable.prefix(needed) {
                            active.removeAll { $0.identity == removed.identity }
                            result.removeAll { $0.identity == removed.identity }
                        }
                        available += needed
                    }
                }
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
        maxSimultaneous: Int,
        preferredSourceObjectIDs: Set<Int> = []
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
                    let lhsPreferred = $0.sourceObjectID.map(preferredSourceObjectIDs.contains) ?? false
                    let rhsPreferred = $1.sourceObjectID.map(preferredSourceObjectIDs.contains) ?? false
                    if lhsPreferred != rhsPreferred { return lhsPreferred }
                    if $0.priority == $1.priority {
                        return $0.identity < $1.identity
                    }
                    return $0.priority > $1.priority
                }
            groups.append(Array(group.prefix(maxSimultaneous)))
        }
        return groups
    }

    private static func enforcePlacementLimits(
        from candidates: [GeneratedNote],
        maxSimultaneous: Int,
        rng: inout SplitMix64
    ) -> [GeneratedNote] {
        guard maxSimultaneous > 0 else { return [] }

        let sorted = candidates.sorted(by: generatedNoteSort)
        var result: [GeneratedNote] = []
        var index = 0

        while index < sorted.count {
            let start = index
            index += 1
            while index < sorted.count, abs(sorted[index].time - sorted[start].time) <= 1e-9 {
                index += 1
            }

            let group = Array(sorted[start..<index])
            let time = group[0].time
            // ponytail: linear active-drag scan, replace with an interval index only if chart size makes generation measurable.
            let activeDrags = result.filter { isDragActive($0, at: time) }
            let availableSlots = max(0, maxSimultaneous - activeDrags.count)
            let availableDragSlots = min(availableSlots, max(0, 2 - activeDrags.count))
            let groupDrags = group.filter { $0.kind == .drag }
            let keptDrags = Array(groupDrags.prefix(availableDragSlots))
            let activeAndKeptDrags = activeDrags + keptDrags
            var usedSlots = activeDrags.count + keptDrags.count

            result.append(contentsOf: keptDrags)

            for tap in group where tap.kind == .tap {
                guard usedSlots < maxSimultaneous,
                      !tapConflictsWithDragSpan(tap, drags: activeAndKeptDrags) else {
                    continue
                }
                result.append(tap)
                usedSlots += 1
            }

            for drag in groupDrags.dropFirst(keptDrags.count) {
                guard activeDrags.count + keptDrags.count >= 2 else { continue }
                let shouldConvert = rng.nextDouble() < 0.75
                guard shouldConvert,
                      usedSlots < maxSimultaneous,
                      !tapConflictsWithDragSpan(drag, drags: activeAndKeptDrags) else {
                    continue
                }
                result.append(
                    GeneratedNote(
                        identity: drag.identity,
                        kind: .tap,
                        time: drag.time,
                        lane: drag.lane,
                        duration: 0,
                        lanePath: [],
                        sourceRole: drag.sourceRole
                    )
                )
                usedSlots += 1
            }
        }

        return result.sorted(by: generatedNoteSort)
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
        role: MusicalRole?,
        centroidValues: [Float],
        laneCount: Int,
        previousLane: Int?,
        occupiedLanes: [Int],
        recentLanes: [Int],
        tuning: GenerationTuning,
        rng: inout SplitMix64
    ) -> Int {
        let centroidPercentile = percentileRank(of: onset.centroid, in: centroidValues)
        let region: ClosedRange<Int>
        switch onset.band {
        case .low:
            region = 0...max(0, (laneCount - 1) / 2)
        case .mid:
            region = max(0, laneCount / 3)...min(laneCount - 1, (laneCount * 2) / 3)
        case .high:
            region = min(laneCount - 1, (laneCount * 2) / 3)...(laneCount - 1)
        }
        let regionWidth = region.upperBound - region.lowerBound + 1
        let bias = role.flatMap { tuning.laneMappingWeights[$0] } ?? 0
        let regionPosition = min(
            regionWidth - 1,
            max(0, Int(floor((centroidPercentile + bias * 0.35 + 0.5) * Double(regionWidth))))
        )
        let baseLane = region.lowerBound + regionPosition
        let direction = rng.nextDouble() < 0.5 ? -1 : 1
        let variation = rng.nextDouble()
        var preferredLane = baseLane
        if previousLane == baseLane, variation < 0.6 {
            preferredLane += direction
        } else if variation < 0.2 {
            preferredLane += direction
        } else if laneCount >= 6, variation > 0.82 {
            preferredLane += direction * 2
        }
        preferredLane = min(region.upperBound, max(region.lowerBound, preferredLane))

        let offsets = [0, 1, -1, 2, -2, 3, -3]
        let orderedCandidates = offsets.map { preferredLane + $0 }
            .filter { $0 >= region.lowerBound && $0 <= region.upperBound }
        for lane in orderedCandidates where !occupiedLanes.contains(lane) {
            // Anti-repeat is probabilistic: strength 1 always avoids repeats, 0 ignores them.
            if !repeatsPattern(candidate: lane, history: recentLanes)
                || rng.nextDouble() > tuning.antiRepeatStrength {
                return lane
            }
        }
        if let lane = orderedCandidates.first(where: { !occupiedLanes.contains($0) }) {
            return lane
        }
        return preferredLane
    }

    private static func repeatsPattern(candidate: Int, history: [Int]) -> Bool {
        if history.count >= 2,
           history[history.count - 1] == candidate,
           history[history.count - 2] == candidate {
            return true
        }
        guard history.count >= 8 else { return false }
        let first = Array(history.suffix(8).prefix(4))
        let second = Array(history.suffix(4))
        return first == second && candidate == first[0]
    }

    private static func percentileRank(of value: Float, in sortedValues: [Float]) -> Double {
        guard let first = sortedValues.first, let last = sortedValues.last else { return 0.5 }
        guard last > first else { return 0.5 }
        let lowerCount = sortedValues.firstIndex(where: { $0 >= value }) ?? sortedValues.count
        return Double(lowerCount) / Double(sortedValues.count - 1)
    }

    private static func snappedSustainDuration(
        candidate: SustainCandidate,
        beat: TimeInterval,
        subdivision: TimeInterval,
        tuning: GenerationTuning
    ) -> TimeInterval {
        let maximum = min(candidate.duration, tuning.dragMaxDuration, min(4, beat * 8))
        guard maximum >= subdivision else { return 0 }
        let snapped = floor(maximum / subdivision) * subdivision
        return snapped < tuning.dragMinDuration ? 0 : snapped
    }

    private static func scheduleMIREvent(_ event: MusicalEvent) -> MusicalEvent {
        // Shift only sustained layers crossing the safety delay; intro taps remain suppressed.
        guard let candidate = event.sustainCandidate,
              let playableCandidate = playableSustainCandidate(candidate),
              playableCandidate.onsetTime != candidate.onsetTime else {
            return event
        }

        var scheduled = event
        scheduled.time = playableCandidate.onsetTime
        scheduled.duration = playableCandidate.duration
        scheduled.sustainCandidate = playableCandidate
        return scheduled
    }

    private static func playableSustainCandidate(_ candidate: SustainCandidate) -> SustainCandidate? {
        let startTime = max(candidate.onsetTime, minimumPlayableNoteTime)
        guard candidate.offsetTime > startTime else { return nil }

        var playable = candidate
        playable.onsetTime = startTime
        playable.duration = candidate.offsetTime - startTime
        playable.pitchContour = candidate.pitchContour.filter { $0.time >= startTime - 1e-9 }
        playable.centroidContour = candidate.centroidContour.filter { $0.time >= startTime - 1e-9 }
        return playable
    }

    private static func snappedDuration(
        gap: TimeInterval,
        beat: TimeInterval,
        subdivision: TimeInterval,
        tuning: GenerationTuning
    ) -> TimeInterval {
        let maximum = min(gap - beat * 0.25, tuning.dragMaxDuration)
        guard maximum >= subdivision else { return 0 }
        let snapped = floor(maximum / subdivision) * subdivision
        return snapped < tuning.dragMinDuration ? 0 : snapped
    }

    private static func makeLanePath(
        startLane: Int,
        duration: TimeInterval,
        laneCount: Int,
        difficulty: Difficulty,
        rng: inout SplitMix64
    ) -> [LaneKeyframe] {
        let maximumDistance = min(
            3,
            max(startLane, laneCount - 1 - startLane)
        )
        let maximumSteps = min(
            maximumDistance,
            Int((duration / minimumLaneStepInterval + 1e-9).rounded(.down))
        )
        guard maximumSteps > 0 else { return [] }

        let minimumDistance = min(
            difficulty == .hell ? min(2, maximumDistance) : 1,
            maximumSteps
        )
        let distance = minimumDistance + rng.nextInt(upperBound: maximumSteps - minimumDistance + 1)
        let canMoveRight = startLane + distance < laneCount
        let canMoveLeft = startLane - distance >= 0
        let direction: Int
        if canMoveRight && canMoveLeft {
            direction = rng.nextDouble() < 0.5 ? -1 : 1
        } else if canMoveRight {
            direction = 1
        } else {
            direction = -1
        }
        return (1...distance).map { step in
            LaneKeyframe(
                offset: duration * Double(step) / Double(distance),
                lane: Double(startLane + direction * step)
            )
        }
    }

    private static func makeContourLanePath(
        candidate: SustainCandidate,
        startLane: Int,
        duration: TimeInterval,
        laneCount: Int
    ) -> [LaneKeyframe] {
        let contour = candidate.pitchContour.count >= 2
            ? candidate.pitchContour
            : candidate.centroidContour
        guard contour.count >= 2, duration >= minimumLaneStepInterval else { return [] }
        let values = contour.map(\.value)
        guard let minimum = values.min(), let maximum = values.max(), maximum > minimum else {
            return []
        }

        let clampedStart = min(laneCount - 1, max(0, startLane))
        // Cap the drag's lane spread to at most 3 adjacent lanes centered on the
        // start lane so a single contour drag can't sweep the whole lane range and
        // block every other lane for its entire duration.
        let laneWindowMin = max(0, clampedStart - 1)
        let laneWindowMax = min(laneCount - 1, clampedStart + 1)

        var currentLane = clampedStart
        var nextOffset = minimumLaneStepInterval
        var path: [LaneKeyframe] = []
        for point in contour.dropFirst() {
            let normalized = Double((point.value - minimum) / (maximum - minimum))
            let rawTargetLane = min(laneCount - 1, max(0, Int((normalized * Double(laneCount - 1)).rounded())))
            let targetLane = min(laneWindowMax, max(laneWindowMin, rawTargetLane))
            while currentLane != targetLane,
                  nextOffset <= duration + 1e-9 {
                let direction = targetLane > currentLane ? 1 : -1
                currentLane += direction
                path.append(
                    LaneKeyframe(
                        offset: min(duration, nextOffset),
                        lane: Double(currentLane)
                    )
                )
                nextOffset += minimumLaneStepInterval
            }
            let contourOffset = min(
                duration,
                max(0, point.time - candidate.onsetTime)
            )
            if contourOffset >= nextOffset, currentLane != targetLane {
                nextOffset = contourOffset
            }
        }
        return path
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

    private static func enforceSameLaneGap(
        from candidates: [GeneratedNote],
        minimumGap: TimeInterval
    ) -> [GeneratedNote] {
        var lastTimeByLane: [Int: TimeInterval] = [:]
        var result: [GeneratedNote] = []
        for candidate in candidates.sorted(by: generatedNoteSort) {
            if let lastTime = lastTimeByLane[candidate.lane],
               candidate.time - lastTime < minimumGap - 1e-9 {
                continue
            }
            result.append(candidate)
            lastTimeByLane[candidate.lane] = candidate.time
        }
        return result
    }

    private static func removeDragSpanConflicts(
        from candidates: [GeneratedNote],
        laneCount: Int,
        maxSimultaneous: Int,
        minimumGap: TimeInterval
    ) -> [GeneratedNote] {
        let drags = candidates.filter { $0.kind == .drag }
        var planned = candidates.sorted(by: generatedNoteSort)
        var index = 0

        while index < planned.count {
            guard planned[index].kind == .tap else {
                index += 1
                continue
            }

            let candidate = planned[index]
            guard tapConflictsWithDragSpan(candidate, drags: drags) else {
                index += 1
                continue
            }

            let relocatedLane = nearestLanes(
                around: candidate.lane,
                laneCount: laneCount
            ).first { lane in
                var relocated = candidate
                relocated.lane = lane
                guard !tapConflictsWithDragSpan(relocated, drags: drags),
                      planned.filter({ abs($0.time - candidate.time) <= 1e-9 }).count <= maxSimultaneous,
                      !planned.contains(where: { other in
                          other.identity != candidate.identity
                              && other.lane == lane
                              && abs(other.time - candidate.time) < minimumGap - 1e-9
                      }) else {
                    return false
                }
                return true
            }

            if let relocatedLane {
                planned[index].lane = relocatedLane
                index += 1
            } else {
                planned.remove(at: index)
            }
        }

        return planned.sorted(by: generatedNoteSort)
    }

    private static func nearestLanes(around lane: Int, laneCount: Int) -> [Int] {
        guard laneCount > 1 else { return [] }
        var result: [Int] = []
        let maximumDistance = max(lane, laneCount - 1 - lane)
        for distance in 1...maximumDistance {
            if lane - distance >= 0 { result.append(lane - distance) }
            if lane + distance < laneCount { result.append(lane + distance) }
        }
        return result
    }

    private static func tapConflictsWithDragSpan(
        _ tap: GeneratedNote,
        drags: [GeneratedNote]
    ) -> Bool {
        drags.contains { drag in
            let dragLanes = [Double(drag.lane)] + drag.lanePath.map(\.lane)
            let minimumLane = Int(floor(dragLanes.min()!))
            let maximumLane = Int(ceil(dragLanes.max()!))
            let dragStart = drag.time - dragSpanPadding
            let dragEnd = drag.time + drag.duration + dragSpanPadding
            let isActive = tap.time >= dragStart - 1e-9
                && tap.time <= dragEnd + 1e-9
            return isActive && tap.lane >= minimumLane && tap.lane <= maximumLane
        }
    }

    private static func isDragActive(_ candidate: GeneratedNote, at time: TimeInterval) -> Bool {
        guard candidate.kind == .drag else { return false }
        return time >= candidate.time - 1e-9
            && time < candidate.time + candidate.duration - 1e-9
    }

    private static func generatedNoteSort(_ lhs: GeneratedNote, _ rhs: GeneratedNote) -> Bool {
        if lhs.time == rhs.time {
            if lhs.lane == rhs.lane {
                if lhs.kind != rhs.kind { return lhs.kind == .drag }
                return lhs.identity < rhs.identity
            }
            return lhs.lane < rhs.lane
        }
        return lhs.time < rhs.time
    }

    private static func beatDuration(for tempo: Double) -> TimeInterval {
        60 / (tempo > 0 ? tempo : 120)
    }

    private static func gridSubdivision(
        for difficulty: Difficulty,
        beat: TimeInterval,
        configuration: AnalyzerConfiguration
    ) -> TimeInterval {
        beat / Double(max(1, configuration.policy(for: difficulty).subdivisionDenominator))
    }

    private static func snappedTime(
        _ time: TimeInterval,
        subdivision: TimeInterval,
        duration: TimeInterval,
        phase: TimeInterval,
        tolerance: TimeInterval
    ) -> TimeInterval {
        let snapped = phase + ((time - phase) / subdivision).rounded() * subdivision
        let resolvedTolerance = min(subdivision * 0.25, tolerance)
        let resolved = abs(snapped - time) <= resolvedTolerance ? snapped : time
        return min(duration, max(0, resolved))
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
