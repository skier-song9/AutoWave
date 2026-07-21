import Foundation

enum MusicalRole: String, Codable, Sendable, Equatable, CaseIterable {
    case drum
    case bass
    case melody
    case vocal
    case accompaniment
}

enum DrumEventKind: String, Codable, Sendable, Equatable {
    case kick
    case snare
    case hihatLike
}

struct ContourPoint: Codable, Sendable, Equatable {
    var time: TimeInterval
    var value: Float
    var confidence: Float
}

struct BeatPosition: Codable, Sendable, Equatable {
    var index: Int
    var time: TimeInterval
    var barIndex: Int
    var beatInBar: Int
    var subdivisionIndex: Int
    var confidence: Float

    init(
        index: Int,
        time: TimeInterval,
        barIndex: Int,
        beatInBar: Int,
        subdivisionIndex: Int = 0,
        confidence: Float
    ) {
        self.index = index
        self.time = time
        self.barIndex = barIndex
        self.beatInBar = beatInBar
        self.subdivisionIndex = subdivisionIndex
        self.confidence = confidence
    }
}

struct BeatGrid: Codable, Sendable, Equatable {
    var tempo: Double
    var beats: [BeatPosition]
    var downbeats: [TimeInterval]
    var confidence: Float

    static func empty(tempo: Double) -> BeatGrid {
        BeatGrid(tempo: tempo, beats: [], downbeats: [], confidence: 0)
    }
}

struct SectionBoundary: Codable, Sendable, Equatable {
    var id: Int
    var startTime: TimeInterval
    var endTime: TimeInterval
    var confidence: Float
}

struct PhraseBoundary: Codable, Sendable, Equatable {
    var id: Int
    var sectionID: Int
    var startTime: TimeInterval
    var endTime: TimeInterval
    var confidence: Float
}

struct HarmonicPercussiveFrame: Codable, Sendable, Equatable {
    var time: TimeInterval
    var harmonicEnergy: Float
    var percussiveEnergy: Float
    var confidence: Float
}

struct DrumEvent: Codable, Sendable, Equatable {
    var id: Int
    var kind: DrumEventKind
    var onsetTime: TimeInterval
    var offsetTime: TimeInterval
    var strength: Float
    var confidence: Float
    var beatAlignedStart: TimeInterval?
    var beatAlignedEnd: TimeInterval?
    var sectionID: Int?
    var phraseID: Int?

    var duration: TimeInterval { max(0, offsetTime - onsetTime) }
}

struct MusicalObject: Codable, Sendable, Equatable {
    var id: Int
    var onsetTime: TimeInterval
    var offsetTime: TimeInterval
    var sourceRole: MusicalRole
    var drumKind: DrumEventKind?
    var meanEnergy: Float
    var sustainStability: Float
    var percussiveness: Float
    var pitchContour: [ContourPoint]
    var centroidContour: [ContourPoint]
    var voicingConfidence: Float
    var beatAlignedStart: TimeInterval?
    var beatAlignedEnd: TimeInterval?
    var sectionID: Int?
    var phraseID: Int?
    var importanceScore: Float
    var confidence: Float

    init(
        id: Int,
        onsetTime: TimeInterval,
        offsetTime: TimeInterval,
        sourceRole: MusicalRole,
        drumKind: DrumEventKind? = nil,
        meanEnergy: Float,
        sustainStability: Float,
        percussiveness: Float,
        pitchContour: [ContourPoint],
        centroidContour: [ContourPoint],
        voicingConfidence: Float,
        beatAlignedStart: TimeInterval? = nil,
        beatAlignedEnd: TimeInterval? = nil,
        sectionID: Int? = nil,
        phraseID: Int? = nil,
        confidence: Float,
        importanceScore: Float
    ) {
        self.id = id
        self.onsetTime = onsetTime
        self.offsetTime = offsetTime
        self.sourceRole = sourceRole
        self.drumKind = drumKind
        self.meanEnergy = meanEnergy
        self.sustainStability = sustainStability
        self.percussiveness = percussiveness
        self.pitchContour = pitchContour
        self.centroidContour = centroidContour
        self.voicingConfidence = voicingConfidence
        self.beatAlignedStart = beatAlignedStart
        self.beatAlignedEnd = beatAlignedEnd
        self.sectionID = sectionID
        self.phraseID = phraseID
        self.importanceScore = importanceScore
        self.confidence = confidence
    }

    var duration: TimeInterval { max(0, offsetTime - onsetTime) }
}

struct SustainCandidate: Codable, Sendable, Equatable {
    var objectID: Int
    var onsetTime: TimeInterval
    var offsetTime: TimeInterval
    var duration: TimeInterval
    var sourceRole: MusicalRole
    var meanEnergy: Float
    var sustainStability: Float
    var percussiveness: Float
    var pitchContour: [ContourPoint]
    var centroidContour: [ContourPoint]
    var voicingConfidence: Float
    var beatAlignedStart: TimeInterval?
    var beatAlignedEnd: TimeInterval?
    var sectionID: Int?
    var phraseID: Int?
    var importanceScore: Float
    var confidence: Float
    var sustainScore: Float

    // Importance wins collisions; confidence, sustain score, and duration break ties, while exact ties retain lhs.
    static func preferred(_ lhs: SustainCandidate, over rhs: SustainCandidate) -> SustainCandidate {
        if lhs.importanceScore != rhs.importanceScore {
            return lhs.importanceScore > rhs.importanceScore ? lhs : rhs
        }
        if lhs.confidence != rhs.confidence {
            return lhs.confidence > rhs.confidence ? lhs : rhs
        }
        if lhs.sustainScore != rhs.sustainScore {
            return lhs.sustainScore > rhs.sustainScore ? lhs : rhs
        }
        if lhs.duration != rhs.duration {
            return lhs.duration > rhs.duration ? lhs : rhs
        }
        return lhs
    }
}

struct StemFrame: Codable, Sendable, Equatable {
    var time: TimeInterval
    var drumEnergy: Float
    var bassEnergy: Float
    var melodyEnergy: Float
    var vocalEnergy: Float
    var accompanimentEnergy: Float
}

struct SectionAnalysis: Codable, Sendable, Equatable {
    var sections: [SectionBoundary]
    var phrases: [PhraseBoundary]
}

struct ContourAnalysis: Codable, Sendable, Equatable {
    var contour: [ContourPoint]
    var objects: [MusicalObject]
}

struct LayerImportanceWeights: Codable, Sendable, Equatable {
    var drum: Float
    var bass: Float
    var melody: Float
    var vocal: Float
    var accompaniment: Float

    func value(for role: MusicalRole) -> Float {
        switch role {
        case .drum: drum
        case .bass: bass
        case .melody: melody
        case .vocal: vocal
        case .accompaniment: accompaniment
        }
    }
}

struct DifficultyLayerPolicy: Codable, Sendable, Equatable {
    var difficulty: Difficulty
    var activeRoles: [MusicalRole]
    var minimumConfidence: Float
    var minimumSustainDuration: TimeInterval
    var npsCap: Double
    var subdivisionDenominator: Int
    var allowsTriplets: Bool
    // How many events sharing the exact same timestamp may be retained on the MIR
    // path before rate-culling; only hard/hell exceed 1 (true chords).
    var maxSimultaneous: Int
    // Minimum spacing enforced between distinct note timestamps for this difficulty.
    var minimumSequentialGap: TimeInterval

    // Kept explicit (rather than relying on the struct's free memberwise init) because
    // a custom init(from:) below suppresses that synthesis.
    init(
        difficulty: Difficulty,
        activeRoles: [MusicalRole],
        minimumConfidence: Float,
        minimumSustainDuration: TimeInterval,
        npsCap: Double,
        subdivisionDenominator: Int,
        allowsTriplets: Bool,
        maxSimultaneous: Int = 1,
        minimumSequentialGap: TimeInterval = 0.09
    ) {
        self.difficulty = difficulty
        self.activeRoles = activeRoles
        self.minimumConfidence = minimumConfidence
        self.minimumSustainDuration = minimumSustainDuration
        self.npsCap = npsCap
        self.subdivisionDenominator = subdivisionDenominator
        self.allowsTriplets = allowsTriplets
        self.maxSimultaneous = maxSimultaneous
        self.minimumSequentialGap = minimumSequentialGap
    }

    // `maxSimultaneous`/`minimumSequentialGap` were added after this type started
    // shipping inside AnalysisResult.configuration, which SwiftData persists
    // (TrackEntity.analysisData). Older on-device JSON won't have these keys, so
    // default them instead of failing the whole AnalysisResult decode.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        difficulty = try container.decode(Difficulty.self, forKey: .difficulty)
        activeRoles = try container.decode([MusicalRole].self, forKey: .activeRoles)
        minimumConfidence = try container.decode(Float.self, forKey: .minimumConfidence)
        minimumSustainDuration = try container.decode(TimeInterval.self, forKey: .minimumSustainDuration)
        npsCap = try container.decode(Double.self, forKey: .npsCap)
        subdivisionDenominator = try container.decode(Int.self, forKey: .subdivisionDenominator)
        allowsTriplets = try container.decode(Bool.self, forKey: .allowsTriplets)
        maxSimultaneous = try container.decodeIfPresent(Int.self, forKey: .maxSimultaneous) ?? 1
        minimumSequentialGap = try container.decodeIfPresent(TimeInterval.self, forKey: .minimumSequentialGap) ?? 0.09
    }

    private enum CodingKeys: String, CodingKey {
        case difficulty
        case activeRoles
        case minimumConfidence
        case minimumSustainDuration
        case npsCap
        case subdivisionDenominator
        case allowsTriplets
        case maxSimultaneous
        case minimumSequentialGap
    }
}

struct AnalyzerConfiguration: Codable, Sendable, Equatable {
    var onsetConfidenceThreshold: Float
    var beatSnapTolerance: TimeInterval
    var subdivisionPolicy: [DifficultyLayerPolicy]
    var sustainStabilityThreshold: Float
    var percussivenessRejectionThreshold: Float
    var layerImportanceWeights: LayerImportanceWeights
    var dragCandidateClutterPenalty: Float
    var contourSmoothingWindow: Int
    var sectionBoundarySensitivity: Float

    // Defaults keep strong transients playable, admit extra layers by difficulty, and require stable contours before dragging.
    static let `default` = AnalyzerConfiguration(
        onsetConfidenceThreshold: 0.22,
        beatSnapTolerance: 0.06,
        subdivisionPolicy: [
            DifficultyLayerPolicy(difficulty: .heaven, activeRoles: [.drum, .melody], minimumConfidence: 0.45, minimumSustainDuration: 0.25, npsCap: 2.4, subdivisionDenominator: 2, allowsTriplets: false, maxSimultaneous: 1, minimumSequentialGap: 0.16),
            DifficultyLayerPolicy(difficulty: .easy, activeRoles: [.drum, .bass, .melody], minimumConfidence: 0.35, minimumSustainDuration: 0.20, npsCap: 4, subdivisionDenominator: 4, allowsTriplets: false, maxSimultaneous: 1, minimumSequentialGap: 0.12),
            DifficultyLayerPolicy(difficulty: .normal, activeRoles: [.drum, .bass, .melody, .vocal], minimumConfidence: 0.28, minimumSustainDuration: 0.125, npsCap: 6, subdivisionDenominator: 4, allowsTriplets: true, maxSimultaneous: 1, minimumSequentialGap: 0.09),
            DifficultyLayerPolicy(difficulty: .hard, activeRoles: [.drum, .bass, .melody, .vocal, .accompaniment], minimumConfidence: 0.22, minimumSustainDuration: 0.125, npsCap: 8.5, subdivisionDenominator: 8, allowsTriplets: true, maxSimultaneous: 2, minimumSequentialGap: 0.075),
            DifficultyLayerPolicy(difficulty: .hell, activeRoles: MusicalRole.allCases, minimumConfidence: 0.16, minimumSustainDuration: 0.125, npsCap: 12, subdivisionDenominator: 8, allowsTriplets: true, maxSimultaneous: 2, minimumSequentialGap: 0.06)
        ],
        sustainStabilityThreshold: 0.52,
        percussivenessRejectionThreshold: 0.76,
        layerImportanceWeights: LayerImportanceWeights(drum: 1, bass: 0.9, melody: 1.1, vocal: 1.2, accompaniment: 0.72),
        dragCandidateClutterPenalty: 0.2,
        contourSmoothingWindow: 3,
        sectionBoundarySensitivity: 0.28
    )

    func policy(for difficulty: Difficulty) -> DifficultyLayerPolicy {
        subdivisionPolicy.first { $0.difficulty == difficulty }
            ?? AnalyzerConfiguration.default.subdivisionPolicy[2]
    }
}

struct AnalyzerInput: Sendable {
    var frames: [SpectralFrame]
    var onsets: [Onset]
    var duration: TimeInterval
    var sampleRate: Double
    var hopSize: Int
    var tempo: Double
    var configuration: AnalyzerConfiguration
    var beatGrid: BeatGrid?
    var separationFrames: [HarmonicPercussiveFrame]
    var sections: [SectionBoundary]
    var phrases: [PhraseBoundary]

    init(
        frames: [SpectralFrame],
        onsets: [Onset],
        duration: TimeInterval,
        sampleRate: Double,
        hopSize: Int,
        tempo: Double,
        configuration: AnalyzerConfiguration,
        beatGrid: BeatGrid? = nil,
        separationFrames: [HarmonicPercussiveFrame] = [],
        sections: [SectionBoundary] = [],
        phrases: [PhraseBoundary] = []
    ) {
        self.frames = frames
        self.onsets = onsets
        self.duration = duration
        self.sampleRate = sampleRate
        self.hopSize = hopSize
        self.tempo = tempo
        self.configuration = configuration
        self.beatGrid = beatGrid
        self.separationFrames = separationFrames
        self.sections = sections
        self.phrases = phrases
    }
}

protocol BeatTracking {
    func track(_ input: AnalyzerInput) throws -> BeatGrid
}

protocol SectionAnalyzing {
    func analyze(_ input: AnalyzerInput) throws -> SectionAnalysis
}

protocol HarmonicPercussiveSeparating {
    func separate(_ input: AnalyzerInput) throws -> [HarmonicPercussiveFrame]
}

protocol DrumEventDetecting {
    func detect(_ input: AnalyzerInput) throws -> [DrumEvent]
}

protocol MelodyTracking {
    func track(_ input: AnalyzerInput) throws -> ContourAnalysis
}

protocol BassTracking {
    func track(_ input: AnalyzerInput) throws -> ContourAnalysis
}

protocol VocalSpanAnalyzing {
    func analyze(_ input: AnalyzerInput) throws -> [MusicalObject]
}

protocol StemSeparating {
    func separate(_ input: AnalyzerInput) throws -> [StemFrame]
}

struct MIRAnalysis: Codable, Sendable, Equatable {
    var beatGrid: BeatGrid
    var sections: [SectionBoundary]
    var phrases: [PhraseBoundary]
    var separationFrames: [HarmonicPercussiveFrame]
    var drumEvents: [DrumEvent]
    var melodyContour: [ContourPoint]
    var bassContour: [ContourPoint]
    var vocalSpans: [MusicalObject]
    var stemFrames: [StemFrame]
    var musicalObjects: [MusicalObject]
    var sustainCandidates: [SustainCandidate]
    var analyzerBackend: String
    var analysisConfidence: Float

    static func empty(tempo: Double) -> MIRAnalysis {
        MIRAnalysis(
            beatGrid: .empty(tempo: tempo),
            sections: [],
            phrases: [],
            separationFrames: [],
            drumEvents: [],
            melodyContour: [],
            bassContour: [],
            vocalSpans: [],
            stemFrames: [],
            musicalObjects: [],
            sustainCandidates: [],
            analyzerBackend: "legacy",
            analysisConfidence: 0
        )
    }
}
