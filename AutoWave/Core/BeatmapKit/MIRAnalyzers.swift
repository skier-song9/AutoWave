import Foundation

struct DSPBeatTracker: BeatTracking {
    func track(_ input: AnalyzerInput) throws -> BeatGrid {
        let tempo = input.tempo > 0 ? input.tempo : 120
        let beatDuration = 60 / tempo
        guard input.duration > 0, beatDuration > 0 else {
            return .empty(tempo: tempo)
        }

        let phase = bestPhase(onsets: input.onsets, beatDuration: beatDuration)
        var beats: [BeatPosition] = []
        var time = phase
        var index = 0
        while time <= input.duration + 1e-9 {
            beats.append(
                BeatPosition(
                    index: index,
                    time: time,
                    barIndex: index / 4,
                    beatInBar: index % 4,
                    confidence: confidence(at: time, onsets: input.onsets, beatDuration: beatDuration)
                )
            )
            time += beatDuration
            index += 1
        }

        let downbeats = beats.filter { $0.beatInBar == 0 }.map(\.time)
        let confidence = beats.isEmpty
            ? 0
            : beats.map(\.confidence).reduce(0, +) / Float(beats.count)
        return BeatGrid(
            tempo: tempo,
            beats: beats,
            downbeats: downbeats,
            confidence: confidence
        )
    }

    private func bestPhase(onsets: [Onset], beatDuration: TimeInterval) -> TimeInterval {
        guard !onsets.isEmpty else { return 0 }
        let resolution = 32
        var bestPhase = 0.0
        var bestScore = -Double.infinity
        for step in 0..<resolution {
            let phase = beatDuration * Double(step) / Double(resolution)
            let score = onsets.reduce(0.0) { total, onset in
                let nearest = phase
                    + ((onset.time - phase) / beatDuration).rounded() * beatDuration
                let distance = abs(onset.time - nearest)
                let alignment = max(0, 1 - distance / (beatDuration * 0.5))
                return total + Double(onset.strength) * alignment
            }
            if score > bestScore {
                bestScore = score
                bestPhase = phase
            }
        }
        return bestPhase
    }

    private func confidence(
        at time: TimeInterval,
        onsets: [Onset],
        beatDuration: TimeInterval
    ) -> Float {
        guard let closest = onsets.min(by: { abs($0.time - time) < abs($1.time - time) }) else {
            return 0.2
        }
        let distance = abs(closest.time - time)
        return Float(max(0.2, 1 - distance / (beatDuration * 0.5)))
    }
}

struct DSPSectionAnalyzer: SectionAnalyzing {
    func analyze(_ input: AnalyzerInput) throws -> SectionAnalysis {
        let tempo = input.tempo > 0 ? input.tempo : 120
        let barDuration = 4 * 60 / tempo
        guard input.duration > 0 else { return SectionAnalysis(sections: [], phrases: []) }

        let barCount = max(1, Int(ceil(input.duration / barDuration)))
        let energies = (0..<barCount).map { bar in
            averageEnergy(
                frames: input.frames,
                start: Double(bar) * barDuration,
                end: min(input.duration, Double(bar + 1) * barDuration),
                input: input
            )
        }
        var sectionStarts = [0]
        for bar in 1..<barCount {
            let previous = energies[bar - 1]
            let current = energies[bar]
            let energyChange = abs(current - previous) / max(0.001, max(current, previous))
            let centroidChange = centroidChange(
                frames: input.frames,
                start: Double(bar) * barDuration,
                end: min(input.duration, Double(bar + 1) * barDuration),
                input: input
            )
            if energyChange >= input.configuration.sectionBoundarySensitivity
                || centroidChange >= 0.35 {
                sectionStarts.append(bar)
            }
        }

        var sections: [SectionBoundary] = []
        for (index, startBar) in sectionStarts.enumerated() {
            let endBar = index + 1 < sectionStarts.count ? sectionStarts[index + 1] : barCount
            let start = Double(startBar) * barDuration
            let end = min(input.duration, Double(endBar) * barDuration)
            sections.append(
                SectionBoundary(
                    id: index,
                    startTime: start,
                    endTime: end,
                    confidence: index == 0 ? 0.65 : 0.8
                )
            )
        }

        var phrases: [PhraseBoundary] = []
        var phraseID = 0
        for section in sections {
            let phraseDuration = barDuration * 4
            var start = section.startTime
            while start < section.endTime - 1e-9 {
                let end = min(section.endTime, start + phraseDuration)
                phrases.append(
                    PhraseBoundary(
                        id: phraseID,
                        sectionID: section.id,
                        startTime: start,
                        endTime: end,
                        confidence: section.confidence
                    )
                )
                phraseID += 1
                start = end
            }
        }
        return SectionAnalysis(sections: sections, phrases: phrases)
    }

    private func averageEnergy(
        frames: [SpectralFrame],
        start: TimeInterval,
        end: TimeInterval,
        input: AnalyzerInput
    ) -> Float {
        let values = frames.enumerated().compactMap { index, frame -> Float? in
            let time = frameTime(index, input: input)
            guard time >= start, time < end else { return nil }
            return frame.rms + frame.flux * 0.15
        }
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Float(values.count)
    }

    private func centroidChange(
        frames: [SpectralFrame],
        start: TimeInterval,
        end: TimeInterval,
        input: AnalyzerInput
    ) -> Float {
        let values = frames.enumerated().compactMap { index, frame -> Float? in
            let time = frameTime(index, input: input)
            guard time >= start, time < end else { return nil }
            return frame.centroid
        }
        guard values.count >= 2 else { return 0 }
        let midpoint = values.count / 2
        let left = values[..<midpoint].reduce(0, +) / Float(max(1, midpoint))
        let right = values[midpoint...].reduce(0, +) / Float(values.count - midpoint)
        return abs(right - left) / max(100, max(left, right))
    }
}

struct DSPHarmonicPercussiveSeparator: HarmonicPercussiveSeparating {
    func separate(_ input: AnalyzerInput) throws -> [HarmonicPercussiveFrame] {
        input.frames.enumerated().map { index, frame in
            let transientRatio = frame.flux / max(0.001, frame.flux + frame.rms)
            let percussive = min(1, max(0, transientRatio))
            return HarmonicPercussiveFrame(
                time: frameTime(index, input: input),
                harmonicEnergy: 1 - percussive,
                percussiveEnergy: percussive,
                confidence: abs((1 - percussive) - percussive)
            )
        }
    }
}

struct DSPDrumEventDetector: DrumEventDetecting {
    func detect(_ input: AnalyzerInput) throws -> [DrumEvent] {
        let bands: [(DrumEventKind, (SpectralFrame) -> Float)] = [
            (.kick, { $0.lowFlux }),
            (.snare, { $0.midFlux }),
            (.hihatLike, { $0.highFlux })
        ]
        var result: [DrumEvent] = []
        var nextID = 0
        for (kind, value) in bands {
            let values = input.frames.map(value)
            guard let maximum = values.max(), maximum > 0 else { continue }
            let threshold = max(maximum * 0.35, input.configuration.onsetConfidenceThreshold * maximum)
            for index in values.indices where values[index] >= threshold {
                let previous = index > 0 ? values[index - 1] : 0
                let next = index + 1 < values.count ? values[index + 1] : 0
                guard values[index] >= previous, values[index] >= next,
                      values[index] > previous || values[index] > next else { continue }
                let time = frameTime(index, input: input)
                result.append(
                    DrumEvent(
                        id: nextID,
                        kind: kind,
                        onsetTime: time,
                        offsetTime: time + max(0.04, frameDuration(input: input)),
                        strength: values[index] / maximum,
                        confidence: min(1, values[index] / max(0.001, threshold)),
                        beatAlignedStart: nearestBeat(time, input: input),
                        beatAlignedEnd: nil,
                        sectionID: sectionID(at: time, input: input),
                        phraseID: phraseID(at: time, input: input)
                    )
                )
                nextID += 1
            }
        }
        return result.sorted {
            if $0.onsetTime == $1.onsetTime { return $0.id < $1.id }
            return $0.onsetTime < $1.onsetTime
        }
    }
}

struct DSPMelodyTracker: MelodyTracking {
    func track(_ input: AnalyzerInput) throws -> ContourAnalysis {
        makeContourAnalysis(
            input: input,
            role: .melody,
            roleAssignments: assignedTonalRoles(input: input)
        )
    }
}

struct DSPBassTracker: BassTracking {
    func track(_ input: AnalyzerInput) throws -> ContourAnalysis {
        makeContourAnalysis(
            input: input,
            role: .bass,
            roleAssignments: assignedTonalRoles(input: input)
        )
    }
}

struct DSPVocalSpanAnalyzer: VocalSpanAnalyzing {
    func analyze(_ input: AnalyzerInput) throws -> [MusicalObject] {
        makeContourAnalysis(
            input: input,
            role: .vocal,
            roleAssignments: assignedTonalRoles(input: input)
        ).objects
    }
}

struct DSPStemSeparator: StemSeparating {
    func separate(_ input: AnalyzerInput) throws -> [StemFrame] {
        input.frames.enumerated().map { index, frame in
            let total = max(0.001, frame.bass + frame.mid + frame.treble)
            let harmonic = 1 - min(1, frame.flux / max(0.001, frame.flux + frame.rms))
            let vocal = frame.pitchConfidence * min(1, frame.mid / total)
            return StemFrame(
                time: frameTime(index, input: input),
                drumEnergy: min(1, frame.flux / max(0.001, frame.flux + frame.rms)),
                bassEnergy: min(1, frame.bass / total),
                melodyEnergy: min(1, harmonic * frame.mid / total),
                vocalEnergy: vocal,
                accompanimentEnergy: min(1, harmonic * frame.treble / total)
            )
        }
    }
}

enum SustainCandidateExtractor {
    static func extract(
        objects: [MusicalObject],
        beatGrid: BeatGrid,
        sections: [SectionBoundary],
        phrases: [PhraseBoundary],
        configuration: AnalyzerConfiguration
    ) -> [SustainCandidate] {
        objects.compactMap { object in
            let minimumDuration = configuration.policy(for: .hard).minimumSustainDuration
            guard object.sourceRole != .drum,
                  object.duration >= minimumDuration,
                  object.sustainStability >= configuration.sustainStabilityThreshold,
                  object.percussiveness < configuration.percussivenessRejectionThreshold,
                  object.meanEnergy > 0.01 else {
                return nil
            }

            let roleBonus: Float = switch object.sourceRole {
            case .vocal: 0.22
            case .melody: 0.18
            case .bass: 0.08
            case .accompaniment: 0.03
            case .drum: -1
            }
            let contourBonus = min(0.18, Float(object.pitchContour.count) * 0.04)
                + min(0.08, Float(object.centroidContour.count) * 0.02)
            let durationScore = min(1, Float(object.duration / 2))
            let nearbyObjectCount = objects.filter {
                $0.id != object.id && abs($0.onsetTime - object.onsetTime) < 0.5
            }.count
            let clutterPenalty = min(
                0.3,
                Float(max(0, nearbyObjectCount - 1)) * configuration.dragCandidateClutterPenalty
            )
            let score = max(0, min(1,
                durationScore * 0.28
                    + object.sustainStability * 0.28
                    + object.confidence * 0.18
                    + object.voicingConfidence * 0.08
                    + roleBonus
                    + contourBonus
                    - object.percussiveness * 0.22
                    - clutterPenalty
            ))
            return SustainCandidate(
                objectID: object.id,
                onsetTime: object.onsetTime,
                offsetTime: object.offsetTime,
                duration: object.duration,
                sourceRole: object.sourceRole,
                meanEnergy: object.meanEnergy,
                sustainStability: object.sustainStability,
                percussiveness: object.percussiveness,
                pitchContour: object.pitchContour,
                centroidContour: object.centroidContour,
                voicingConfidence: object.voicingConfidence,
                beatAlignedStart: alignedTime(object.onsetTime, beatGrid: beatGrid, tolerance: configuration.beatSnapTolerance),
                beatAlignedEnd: alignedTime(object.offsetTime, beatGrid: beatGrid, tolerance: configuration.beatSnapTolerance),
                sectionID: structureID(at: object.onsetTime, sections: sections, id: { $0.id }),
                phraseID: structureID(at: object.onsetTime, sections: phrases, id: { $0.id }),
                importanceScore: object.importanceScore,
                confidence: object.confidence,
                sustainScore: score
            )
        }
        .enumerated()
        .sorted {
            if $0.element.sustainScore == $1.element.sustainScore {
                if $0.element.objectID == $1.element.objectID {
                    return $0.offset < $1.offset
                }
                return $0.element.objectID < $1.element.objectID
            }
            return $0.element.sustainScore > $1.element.sustainScore
        }
        .map(\.element)
    }
}

enum MIRAnalysisPipeline {
    static func analyze(input: AnalyzerInput) -> MIRAnalysis {
        let beatGrid = run({ try DSPBeatTracker().track(input) }, fallback: { .empty(tempo: input.tempo) })
        var beatInput = input
        beatInput.beatGrid = beatGrid

        let separation = run({ try DSPHarmonicPercussiveSeparator().separate(beatInput) }, fallback: { [] })
        beatInput.separationFrames = separation
        let structure = run({ try DSPSectionAnalyzer().analyze(beatInput) }, fallback: { SectionAnalysis(sections: [], phrases: []) })
        beatInput.sections = structure.sections
        beatInput.phrases = structure.phrases

        let drums = run({ try DSPDrumEventDetector().detect(beatInput) }, fallback: { [] })
        let melody = run({ try DSPMelodyTracker().track(beatInput) }, fallback: { ContourAnalysis(contour: [], objects: []) })
        let bass = run({ try DSPBassTracker().track(beatInput) }, fallback: { ContourAnalysis(contour: [], objects: []) })
        let vocals = run({ try DSPVocalSpanAnalyzer().analyze(beatInput) }, fallback: { [] })
        let stems = run({ try DSPStemSeparator().separate(beatInput) }, fallback: { [] })

        var objects = drums.map { event in
            MusicalObject(
                id: 10_000 + event.id,
                onsetTime: event.onsetTime,
                offsetTime: event.offsetTime,
                sourceRole: .drum,
                drumKind: event.kind,
                meanEnergy: event.strength,
                sustainStability: 0,
                percussiveness: 1,
                pitchContour: [],
                centroidContour: [],
                voicingConfidence: 0,
                beatAlignedStart: event.beatAlignedStart,
                beatAlignedEnd: event.beatAlignedEnd,
                sectionID: event.sectionID,
                phraseID: event.phraseID,
                confidence: event.confidence,
                importanceScore: event.strength
            )
        }
        objects.append(contentsOf: melody.objects)
        objects.append(contentsOf: bass.objects)
        objects.append(contentsOf: vocals)
        objects.append(contentsOf: accompanimentObjects(input: beatInput, startingID: 20_000))
        objects = assignGlobalObjectIDs(objects.map { annotate($0, input: beatInput) })

        let candidates = SustainCandidateExtractor.extract(
            objects: objects,
            beatGrid: beatGrid,
            sections: structure.sections,
            phrases: structure.phrases,
            configuration: input.configuration
        )
        let confidenceValues = objects.map(\.confidence)
        let confidence = confidenceValues.isEmpty
            ? 0
            : confidenceValues.reduce(0, +) / Float(confidenceValues.count)
        return MIRAnalysis(
            beatGrid: beatGrid,
            sections: structure.sections,
            phrases: structure.phrases,
            separationFrames: separation,
            drumEvents: drums,
            melodyContour: melody.contour,
            bassContour: bass.contour,
            vocalSpans: objects.filter { $0.sourceRole == .vocal },
            stemFrames: stems,
            musicalObjects: objects,
            sustainCandidates: candidates,
            analyzerBackend: "dsp.v1",
            analysisConfidence: confidence
        )
    }

    private static func run<T>(_ operation: () throws -> T, fallback: () -> T) -> T {
        (try? operation()) ?? fallback()
    }

    private static func accompanimentObjects(input: AnalyzerInput, startingID: Int) -> [MusicalObject] {
        // Normalize against the track-wide accompaniment band (mid) energy, mirroring the
        // drum tracker's value/maximum pattern, so importanceScore lands in 0-1 like the
        // other roles instead of the raw ~1e-3 band magnitude.
        let midValues = input.frames.map(\.mid)
        guard let maximum = midValues.max(), maximum > 0 else { return [] }

        let qualifying = input.frames.enumerated().filter { _, frame in
            frame.mid > frame.bass * 1.1
                && frame.mid > frame.treble * 1.1
                && frame.pitchConfidence < 0.55
                && frame.flux < max(0.01, frame.rms * 1.5)
        }
        guard !qualifying.isEmpty else { return [] }

        // Merge contiguous qualifying frames into runs first (otherwise every single frame
        // becomes its own object), then merge runs that are closer than the minimum spacing
        // so the layer can't flood once the importance filter stops rejecting it outright.
        let accompanimentMinimumGap: TimeInterval = 0.18
        var runs: [[(offset: Int, element: SpectralFrame)]] = []
        var runStart = 0
        for index in 1...qualifying.count {
            let isRunEnd = index == qualifying.count
                || qualifying[index].offset != qualifying[index - 1].offset + 1
            guard isRunEnd else { continue }
            runs.append(Array(qualifying[runStart..<index]))
            runStart = index
        }

        var mergedRuns: [[(offset: Int, element: SpectralFrame)]] = []
        for run in runs {
            if let lastFrame = mergedRuns.last?.last, let firstFrame = run.first {
                let previousEnd = frameTime(lastFrame.offset + 1, input: input)
                let currentStart = frameTime(firstFrame.offset, input: input)
                if currentStart - previousEnd < accompanimentMinimumGap {
                    mergedRuns[mergedRuns.count - 1].append(contentsOf: run)
                    continue
                }
            }
            mergedRuns.append(run)
        }

        return mergedRuns.map { run in
            let startTime = frameTime(run[0].offset, input: input)
            let endTime = frameTime(run.last!.offset + 1, input: input)
            let meanMid = run.map { $0.element.mid }.reduce(0, +) / Float(run.count)
            let meanCentroid = run.map { $0.element.centroid }.reduce(0, +) / Float(run.count)
            return MusicalObject(
                id: startingID + run[0].offset,
                onsetTime: startTime,
                offsetTime: endTime,
                sourceRole: .accompaniment,
                meanEnergy: meanMid,
                sustainStability: 0.6,
                percussiveness: 0.15,
                pitchContour: [],
                centroidContour: [ContourPoint(time: startTime, value: meanCentroid, confidence: 0.6)],
                voicingConfidence: 0,
                confidence: 0.55,
                importanceScore: min(1, meanMid / maximum)
            )
        }
    }

    private static func assignGlobalObjectIDs(_ objects: [MusicalObject]) -> [MusicalObject] {
        let ordered = objects.enumerated().sorted { lhs, rhs in
            let left = lhs.element
            let right = rhs.element
            if left.onsetTime != right.onsetTime { return left.onsetTime < right.onsetTime }
            if left.offsetTime != right.offsetTime { return left.offsetTime < right.offsetTime }
            if left.sourceRole != right.sourceRole {
                return roleOrder(left.sourceRole) < roleOrder(right.sourceRole)
            }
            if left.id != right.id { return left.id < right.id }
            return lhs.offset < rhs.offset
        }
        return ordered.enumerated().map { index, item in
            var object = item.element
            // IDs are assigned after every analyzer is merged, so frame indices cannot collide across layers.
            object.id = index + 1
            return object
        }
    }

    private static func roleOrder(_ role: MusicalRole) -> Int {
        switch role {
        case .drum: 0
        case .bass: 1
        case .melody: 2
        case .vocal: 3
        case .accompaniment: 4
        }
    }

    private static func annotate(_ object: MusicalObject, input: AnalyzerInput) -> MusicalObject {
        var result = object
        result.beatAlignedStart = result.beatAlignedStart ?? nearestBeat(result.onsetTime, input: input)
        result.beatAlignedEnd = result.beatAlignedEnd ?? nearestBeat(result.offsetTime, input: input)
        result.sectionID = result.sectionID ?? sectionID(at: result.onsetTime, input: input)
        result.phraseID = result.phraseID ?? phraseID(at: result.onsetTime, input: input)
        return result
    }
}

/// The three tonal roles (bass/vocal/melody) have overlapping frequency ranges, so a single
/// frame can qualify for more than one. Each case's `logCenter` (log of the geometric mean of
/// its bounds) lets us pick the single nearest-in-log-frequency role per frame instead of
/// emitting one event per matching role.
private enum TonalRoleRange: CaseIterable {
    case bass
    case vocal
    case melody

    var musicalRole: MusicalRole {
        switch self {
        case .bass: return .bass
        case .vocal: return .vocal
        case .melody: return .melody
        }
    }

    var frequencyRange: ClosedRange<Float> {
        switch self {
        case .bass: return 40...250
        case .vocal: return 150...1_200
        case .melody: return 180...3_000
        }
    }

    var logCenter: Float {
        let range = frequencyRange
        return logf(sqrtf(range.lowerBound * range.upperBound))
    }
}

/// Computes, per frame, at most one tonal role (bass/vocal/melody) or `nil` if the frame
/// doesn't qualify for any of them. This is the single source of truth the melody/bass/vocal
/// trackers all consult so a frame can never mint events for more than one role.
private func assignedTonalRoles(input: AnalyzerInput) -> [MusicalRole?] {
    let threshold = input.configuration.onsetConfidenceThreshold
    return input.frames.map { frame -> MusicalRole? in
        guard frame.pitchConfidence >= threshold else { return nil }
        let candidates = TonalRoleRange.allCases.filter { $0.frequencyRange.contains(frame.dominantFrequency) }
        guard !candidates.isEmpty else { return nil }
        guard candidates.count > 1 else { return candidates[0].musicalRole }
        guard frame.dominantFrequency > 0 else { return candidates[0].musicalRole }
        let logFrequency = logf(frame.dominantFrequency)
        let nearest = candidates.min {
            abs($0.logCenter - logFrequency) < abs($1.logCenter - logFrequency)
        }
        return nearest?.musicalRole
    }
}

private func makeContourAnalysis(
    input: AnalyzerInput,
    role: MusicalRole,
    roleAssignments: [MusicalRole?]
) -> ContourAnalysis {
    let selected = input.frames.enumerated().filter { index, _ in roleAssignments[index] == role }
    guard !selected.isEmpty else { return ContourAnalysis(contour: [], objects: []) }

    let rawContour = selected.map { index, frame in
        ContourPoint(
            time: frameTime(index, input: input),
            value: frame.dominantFrequency,
            confidence: frame.pitchConfidence
        )
    }
    let contour = smoothContour(rawContour, window: input.configuration.contourSmoothingWindow)

    // Re-segmentation cap: 2 beat intervals when tempo is known, otherwise a fixed 0.6s.
    let maxSegmentDuration: TimeInterval = input.tempo > 0 ? 2 * (60.0 / input.tempo) : 0.6

    var objects: [MusicalObject] = []
    var runStart = 0
    for index in 1...selected.count {
        let isRunEnd = index == selected.count
            || selected[index].offset != selected[index - 1].offset + 1
        guard isRunEnd else { continue }

        let runSlice = Array(selected[runStart..<index])
        let segments = splitContiguousRun(runSlice, input: input, maxSegmentDuration: maxSegmentDuration)

        var segmentGlobalStart = runStart
        for segment in segments {
            let segmentGlobalEnd = segmentGlobalStart + segment.count
            let points = Array(contour[segmentGlobalStart..<segmentGlobalEnd])
            objects.append(makeMusicalObject(slice: segment, points: points, role: role, input: input))
            segmentGlobalStart = segmentGlobalEnd
        }
        runStart = index
    }
    return ContourAnalysis(contour: contour, objects: objects)
}

/// Splits a contiguous run of same-role frames into phrase-sized segments at any of:
/// a >6% relative jump in dominantFrequency between adjacent frames, an energy dip below
/// 60% of the segment's running peak, or the segment reaching `maxSegmentDuration`.
/// Without this, a long sustained tone collapses into a single MusicalObject and starves
/// everything after the intro.
private func splitContiguousRun(
    _ slice: [(offset: Int, element: SpectralFrame)],
    input: AnalyzerInput,
    maxSegmentDuration: TimeInterval
) -> [[(offset: Int, element: SpectralFrame)]] {
    guard slice.count > 1 else { return [slice] }

    var segments: [[(offset: Int, element: SpectralFrame)]] = []
    var segmentStart = 0
    var peakEnergy = slice[0].element.rms
    var segmentStartTime = frameTime(slice[0].offset, input: input)

    for index in 1..<slice.count {
        let previousFrequency = slice[index - 1].element.dominantFrequency
        let currentFrequency = slice[index].element.dominantFrequency
        let relativeJump: Float = previousFrequency > 0
            ? abs(currentFrequency - previousFrequency) / previousFrequency
            : 0
        let energyDip = slice[index].element.rms < peakEnergy * 0.6
        let currentEndTime = frameTime(slice[index].offset + 1, input: input)
        let durationExceeded = (currentEndTime - segmentStartTime) >= maxSegmentDuration

        if relativeJump > 0.06 || energyDip || durationExceeded {
            segments.append(Array(slice[segmentStart..<index]))
            segmentStart = index
            peakEnergy = slice[index].element.rms
            segmentStartTime = frameTime(slice[index].offset, input: input)
        } else {
            peakEnergy = max(peakEnergy, slice[index].element.rms)
        }
    }
    segments.append(Array(slice[segmentStart...]))
    return segments
}

private func makeMusicalObject(
    slice: [(offset: Int, element: SpectralFrame)],
    points: [ContourPoint],
    role: MusicalRole,
    input: AnalyzerInput
) -> MusicalObject {
    let startTime = frameTime(slice[0].offset, input: input)
    let endTime = frameTime(slice.last!.offset + 1, input: input)
    let meanEnergy = slice.map { $0.element.rms }.reduce(0, +) / Float(slice.count)
    let meanConfidence = slice.map { $0.element.pitchConfidence }.reduce(0, +) / Float(slice.count)
    let pitchValues = points.map(\.value)
    let meanPitch = pitchValues.reduce(0, +) / Float(pitchValues.count)
    let variance = pitchValues.map { ($0 - meanPitch) * ($0 - meanPitch) }.reduce(0, +) / Float(pitchValues.count)
    let stability = max(0, min(1, 1 - sqrtf(variance) / max(40, meanPitch)))
    let centroids = smoothContour(
        slice.map { offset, frame in
            ContourPoint(time: frameTime(offset, input: input), value: frame.centroid, confidence: meanConfidence)
        },
        window: input.configuration.contourSmoothingWindow
    )
    return MusicalObject(
        id: roleID(role: role, start: slice[0].offset),
        onsetTime: startTime,
        offsetTime: endTime,
        sourceRole: role,
        meanEnergy: meanEnergy,
        sustainStability: stability,
        percussiveness: input.separationFrames.isEmpty ? 0.2 : meanPercussiveness(slice: slice, input: input),
        pitchContour: points,
        centroidContour: centroids,
        voicingConfidence: meanConfidence,
        confidence: meanConfidence,
        importanceScore: min(1, meanEnergy * meanConfidence * 2)
    )
}

private func smoothContour(_ points: [ContourPoint], window: Int) -> [ContourPoint] {
    guard points.count > 2, window > 1 else { return points }
    let radius = max(1, window / 2)
    return points.indices.map { index in
        let lower = max(0, index - radius)
        let upper = min(points.count - 1, index + radius)
        let values = points[lower...upper]
        return ContourPoint(
            time: points[index].time,
            value: values.map(\.value).reduce(0, +) / Float(values.count),
            confidence: values.map(\.confidence).reduce(0, +) / Float(values.count)
        )
    }
}

private func meanPercussiveness(
    slice: [(offset: Int, element: SpectralFrame)],
    input: AnalyzerInput
) -> Float {
    let values = slice.map { offset, _ in
        input.separationFrames.indices.contains(offset)
            ? input.separationFrames[offset].percussiveEnergy
            : 0.2
    }
    return values.reduce(0, +) / Float(max(1, values.count))
}

private func roleID(role: MusicalRole, start: Int) -> Int {
    let namespace: Int64 = switch role {
    case .bass: 1
    case .melody: 2
    case .vocal: 3
    case .drum: 4
    case .accompaniment: 5
    }
    return Int((namespace << 32) | Int64(start))
}

private func frameTime(_ index: Int, input: AnalyzerInput) -> TimeInterval {
    TimeInterval(index * input.hopSize) / max(1, input.sampleRate)
}

private func frameDuration(input: AnalyzerInput) -> TimeInterval {
    TimeInterval(input.hopSize) / max(1, input.sampleRate)
}

private func nearestBeat(_ time: TimeInterval, input: AnalyzerInput) -> TimeInterval? {
    guard let beat = input.beatGrid?.beats.min(by: { abs($0.time - time) < abs($1.time - time) }) else {
        return nil
    }
    let tolerance = input.configuration.beatSnapTolerance
    return abs(beat.time - time) <= tolerance ? beat.time : nil
}

private func alignedTime(
    _ time: TimeInterval,
    beatGrid: BeatGrid,
    tolerance: TimeInterval
) -> TimeInterval? {
    guard let beat = beatGrid.beats.min(by: { abs($0.time - time) < abs($1.time - time) }) else {
        return nil
    }
    return abs(beat.time - time) <= tolerance ? beat.time : nil
}

private func sectionID(at time: TimeInterval, input: AnalyzerInput) -> Int? {
    structureID(at: time, sections: input.sections, id: { $0.id })
}

private func phraseID(at time: TimeInterval, input: AnalyzerInput) -> Int? {
    structureID(at: time, sections: input.phrases, id: { $0.id })
}

private func structureID<T>(
    at time: TimeInterval,
    sections: [T],
    id: (T) -> Int
) -> Int? {
    if let section = sections.first(where: { item in
        if let section = item as? SectionBoundary {
            return time >= section.startTime && time < section.endTime
        }
        if let phrase = item as? PhraseBoundary {
            return time >= phrase.startTime && time < phrase.endTime
        }
        return false
    }) {
        return id(section)
    }
    return nil
}
