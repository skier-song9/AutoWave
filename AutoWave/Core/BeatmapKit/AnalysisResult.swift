import Foundation

enum OnsetBand: String, Codable, Sendable, Equatable {
    case low
    case mid
    case high
}

struct Onset: Codable, Sendable, Equatable {
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

enum AnalysisResultCodingError: Error, Sendable, Equatable {
    case missingVersion
    case unsupportedVersion(Int)
}

struct AnalysisResult: Codable, Sendable, Equatable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int
    var duration: TimeInterval
    var tempo: Double
    var onsets: [Onset]
    var meanBass: Float
    var meanMid: Float
    var meanTreble: Float
    var meanRMS: Float
    var intensityCurve: [Float]
    var analyzerBackend: String
    var configuration: AnalyzerConfiguration
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
    var analysisConfidence: Float

    init(
        duration: TimeInterval,
        tempo: Double,
        onsets: [Onset],
        meanBass: Float,
        meanMid: Float,
        meanTreble: Float,
        meanRMS: Float,
        intensityCurve: [Float] = [],
        schemaVersion: Int = AnalysisResult.currentSchemaVersion,
        analyzerBackend: String = "legacy",
        configuration: AnalyzerConfiguration = .default,
        beatGrid: BeatGrid? = nil,
        sections: [SectionBoundary] = [],
        phrases: [PhraseBoundary] = [],
        separationFrames: [HarmonicPercussiveFrame] = [],
        drumEvents: [DrumEvent] = [],
        melodyContour: [ContourPoint] = [],
        bassContour: [ContourPoint] = [],
        vocalSpans: [MusicalObject] = [],
        stemFrames: [StemFrame] = [],
        musicalObjects: [MusicalObject] = [],
        sustainCandidates: [SustainCandidate] = [],
        analysisConfidence: Float = 0
    ) {
        self.schemaVersion = schemaVersion
        self.duration = duration
        self.tempo = tempo
        self.onsets = onsets
        self.meanBass = meanBass
        self.meanMid = meanMid
        self.meanTreble = meanTreble
        self.meanRMS = meanRMS
        self.intensityCurve = intensityCurve
        self.analyzerBackend = analyzerBackend
        self.configuration = configuration
        self.beatGrid = beatGrid ?? .empty(tempo: tempo)
        self.sections = sections
        self.phrases = phrases
        self.separationFrames = separationFrames
        self.drumEvents = drumEvents
        self.melodyContour = melodyContour
        self.bassContour = bassContour
        self.vocalSpans = vocalSpans
        self.stemFrames = stemFrames
        self.musicalObjects = musicalObjects
        self.sustainCandidates = sustainCandidates
        self.analysisConfidence = analysisConfidence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) else {
            throw AnalysisResultCodingError.missingVersion
        }
        guard schemaVersion == Self.currentSchemaVersion else {
            throw AnalysisResultCodingError.unsupportedVersion(schemaVersion)
        }

        self.schemaVersion = schemaVersion
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        tempo = try container.decode(Double.self, forKey: .tempo)
        onsets = try container.decode([Onset].self, forKey: .onsets)
        meanBass = try container.decode(Float.self, forKey: .meanBass)
        meanMid = try container.decode(Float.self, forKey: .meanMid)
        meanTreble = try container.decode(Float.self, forKey: .meanTreble)
        meanRMS = try container.decode(Float.self, forKey: .meanRMS)
        intensityCurve = try container.decodeIfPresent([Float].self, forKey: .intensityCurve) ?? []
        analyzerBackend = try container.decodeIfPresent(String.self, forKey: .analyzerBackend) ?? "legacy"
        configuration = try container.decodeIfPresent(AnalyzerConfiguration.self, forKey: .configuration) ?? .default
        beatGrid = try container.decodeIfPresent(BeatGrid.self, forKey: .beatGrid) ?? .empty(tempo: tempo)
        sections = try container.decodeIfPresent([SectionBoundary].self, forKey: .sections) ?? []
        phrases = try container.decodeIfPresent([PhraseBoundary].self, forKey: .phrases) ?? []
        separationFrames = try container.decodeIfPresent([HarmonicPercussiveFrame].self, forKey: .separationFrames) ?? []
        drumEvents = try container.decodeIfPresent([DrumEvent].self, forKey: .drumEvents) ?? []
        melodyContour = try container.decodeIfPresent([ContourPoint].self, forKey: .melodyContour) ?? []
        bassContour = try container.decodeIfPresent([ContourPoint].self, forKey: .bassContour) ?? []
        vocalSpans = try container.decodeIfPresent([MusicalObject].self, forKey: .vocalSpans) ?? []
        stemFrames = try container.decodeIfPresent([StemFrame].self, forKey: .stemFrames) ?? []
        musicalObjects = try container.decodeIfPresent([MusicalObject].self, forKey: .musicalObjects) ?? []
        sustainCandidates = try container.decodeIfPresent([SustainCandidate].self, forKey: .sustainCandidates) ?? []
        analysisConfidence = try container.decodeIfPresent(Float.self, forKey: .analysisConfidence) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(duration, forKey: .duration)
        try container.encode(tempo, forKey: .tempo)
        try container.encode(onsets, forKey: .onsets)
        try container.encode(meanBass, forKey: .meanBass)
        try container.encode(meanMid, forKey: .meanMid)
        try container.encode(meanTreble, forKey: .meanTreble)
        try container.encode(meanRMS, forKey: .meanRMS)
        try container.encode(intensityCurve, forKey: .intensityCurve)
        try container.encode(analyzerBackend, forKey: .analyzerBackend)
        try container.encode(configuration, forKey: .configuration)
        try container.encode(beatGrid, forKey: .beatGrid)
        try container.encode(sections, forKey: .sections)
        try container.encode(phrases, forKey: .phrases)
        try container.encode(separationFrames, forKey: .separationFrames)
        try container.encode(drumEvents, forKey: .drumEvents)
        try container.encode(melodyContour, forKey: .melodyContour)
        try container.encode(bassContour, forKey: .bassContour)
        try container.encode(vocalSpans, forKey: .vocalSpans)
        try container.encode(stemFrames, forKey: .stemFrames)
        try container.encode(musicalObjects, forKey: .musicalObjects)
        try container.encode(sustainCandidates, forKey: .sustainCandidates)
        try container.encode(analysisConfidence, forKey: .analysisConfidence)
    }

    static func decodePersisted(_ data: Data) -> AnalysisResult? {
        try? JSONDecoder().decode(AnalysisResult.self, from: data)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case duration
        case tempo
        case onsets
        case meanBass
        case meanMid
        case meanTreble
        case meanRMS
        case intensityCurve
        case analyzerBackend
        case configuration
        case beatGrid
        case sections
        case phrases
        case separationFrames
        case drumEvents
        case melodyContour
        case bassContour
        case vocalSpans
        case stemFrames
        case musicalObjects
        case sustainCandidates
        case analysisConfidence
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

        let configuration = AnalyzerConfiguration.default
        let mir = MIRAnalysisPipeline.analyze(
            input: AnalyzerInput(
                frames: spectral.frames,
                onsets: onsets,
                duration: decoded.duration,
                sampleRate: decoded.sampleRate,
                hopSize: SpectralAnalyzer.hopSize,
                tempo: tempo,
                configuration: configuration
            )
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
            intensityCurve: intensityCurve,
            analyzerBackend: mir.analyzerBackend,
            configuration: configuration,
            beatGrid: mir.beatGrid,
            sections: mir.sections,
            phrases: mir.phrases,
            separationFrames: mir.separationFrames,
            drumEvents: mir.drumEvents,
            melodyContour: mir.melodyContour,
            bassContour: mir.bassContour,
            vocalSpans: mir.vocalSpans,
            stemFrames: mir.stemFrames,
            musicalObjects: mir.musicalObjects,
            sustainCandidates: mir.sustainCandidates,
            analysisConfidence: mir.analysisConfidence
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
