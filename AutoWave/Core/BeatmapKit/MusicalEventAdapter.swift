import Foundation

struct MusicalEvent: Codable, Sendable, Equatable {
    var id: Int
    var time: TimeInterval
    var duration: TimeInterval
    var sourceRole: MusicalRole
    var sourceObjectID: Int
    var confidence: Float
    var importance: Float
    var isSustained: Bool
    var sustainCandidate: SustainCandidate?
}

enum MusicalEventAdapter {
    static func events(
        from analysis: AnalysisResult,
        difficulty: Difficulty,
        configuration: AnalyzerConfiguration
    ) -> [MusicalEvent] {
        guard !analysis.musicalObjects.isEmpty else { return [] }
        let policy = configuration.policy(for: difficulty)
        // Persisted or hand-built analyses may repeat an object ID; prefer musical importance instead of trapping.
        let candidatesByObjectID = Dictionary(
            analysis.sustainCandidates.map { ($0.objectID, $0) },
            uniquingKeysWith: { SustainCandidate.preferred($0, over: $1) }
        )
        return analysis.musicalObjects
            .filter { object in
                policy.activeRoles.contains(object.sourceRole)
                    && object.confidence >= policy.minimumConfidence
                    && object.importanceScore * configuration.layerImportanceWeights.value(for: object.sourceRole) >= policy.minimumConfidence * 0.5
            }
            .map { object in
                MusicalEvent(
                    id: object.id,
                    time: object.onsetTime,
                    duration: object.duration,
                    sourceRole: object.sourceRole,
                    sourceObjectID: object.id,
                    confidence: object.confidence,
                    importance: object.importanceScore,
                    isSustained: candidatesByObjectID[object.id] != nil,
                    sustainCandidate: candidatesByObjectID[object.id]
                )
            }
            .enumerated()
            .sorted {
                if $0.element.time == $1.element.time {
                    if $0.element.sourceRole == $1.element.sourceRole {
                        if $0.element.id == $1.element.id {
                            return $0.offset < $1.offset
                        }
                        return $0.element.id < $1.element.id
                    }
                    return roleOrder($0.element.sourceRole) < roleOrder($1.element.sourceRole)
                }
                return $0.element.time < $1.element.time
            }
            .map(\.element)
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
}

struct DebugFinalNote: Codable, Sendable, Equatable {
    var time: TimeInterval
    var lane: Double
    var kind: NoteKind
    var duration: TimeInterval
    var sourceRole: MusicalRole?
}

struct DifficultyDebugStatistics: Codable, Sendable, Equatable {
    var difficulty: Difficulty
    var selectedEventCount: Int
    var selectedEventCountsByRole: [String: Int]
    var finalNoteCount: Int
    var dragCount: Int
    var excludedReasons: [String]
}

struct AnalysisDebugDocument: Codable, Sendable, Equatable {
    var analyzerBackend: String
    var configuration: AnalyzerConfiguration
    var beats: [BeatPosition]
    var downbeats: [TimeInterval]
    var sections: [SectionBoundary]
    var phrases: [PhraseBoundary]
    var extractedMusicalObjects: [MusicalObject]
    var sustainCandidates: [SustainCandidate]
    var selectedEventCounts: [String: Int]
    var excludedReasons: [String]
    var finalNotes: [DebugFinalNote]
    var difficultyStatistics: [DifficultyDebugStatistics]
}

enum DebugJSONExporter {
    static func export(
        analysis: AnalysisResult,
        beatmaps: [Beatmap]
    ) throws -> Data {
        var selectedEventCounts: [String: Int] = [:]
        var excludedReasons: [String] = []
        var statistics: [DifficultyDebugStatistics] = []
        var finalNotes: [DebugFinalNote] = []

        for difficulty in Difficulty.allCases {
            guard let beatmap = beatmaps.first(where: { $0.difficulty == difficulty }) else { continue }
            let events = MusicalEventAdapter.events(
                from: analysis,
                difficulty: difficulty,
                configuration: analysis.configuration
            )
            var counts: [String: Int] = [:]
            for event in events {
                counts[event.sourceRole.rawValue, default: 0] += 1
            }
            selectedEventCounts[difficulty.rawValue] = events.count
            for (role, count) in counts {
                selectedEventCounts["\(difficulty.rawValue).\(role)"] = count
            }

            let policy = analysis.configuration.policy(for: difficulty)
            let excludedForRole = analysis.musicalObjects.filter {
                !policy.activeRoles.contains($0.sourceRole)
            }.count
            let excludedForConfidence = analysis.musicalObjects.filter {
                policy.activeRoles.contains($0.sourceRole)
                    && $0.confidence < policy.minimumConfidence
            }.count
            var reasons: [String] = []
            if excludedForRole > 0 {
                reasons.append("\(excludedForRole) objects excluded by \(difficulty.rawValue) layer policy")
            }
            if excludedForConfidence > 0 {
                reasons.append("\(excludedForConfidence) objects excluded below confidence threshold")
            }
            excludedReasons.append(contentsOf: reasons)

            statistics.append(
                DifficultyDebugStatistics(
                    difficulty: difficulty,
                    selectedEventCount: events.count,
                    selectedEventCountsByRole: counts,
                    finalNoteCount: beatmap.notes.count,
                    dragCount: beatmap.notes.filter { $0.kind == .drag }.count,
                    excludedReasons: reasons
                )
            )
            finalNotes.append(contentsOf: beatmap.notes.map {
                DebugFinalNote(
                    time: $0.time,
                    lane: $0.lane,
                    kind: $0.kind,
                    duration: $0.duration,
                    sourceRole: $0.sourceRole
                )
            })
        }

        let document = AnalysisDebugDocument(
            analyzerBackend: analysis.analyzerBackend,
            configuration: analysis.configuration,
            beats: analysis.beatGrid.beats,
            downbeats: analysis.beatGrid.downbeats,
            sections: analysis.sections,
            phrases: analysis.phrases,
            extractedMusicalObjects: analysis.musicalObjects,
            sustainCandidates: analysis.sustainCandidates,
            selectedEventCounts: selectedEventCounts,
            excludedReasons: excludedReasons,
            finalNotes: finalNotes,
            difficultyStatistics: statistics
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }
}

extension BeatmapKit {
    static func exportDebugJSON(
        analysis: AnalysisResult,
        beatmaps: [Beatmap]
    ) throws -> Data {
        try DebugJSONExporter.export(analysis: analysis, beatmaps: beatmaps)
    }
}
