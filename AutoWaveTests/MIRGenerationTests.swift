import Foundation
import XCTest
@testable import AutoWave

final class MIRGenerationTests: XCTestCase {
    func testAnalyzerDefaultsMatchPlaygroundDifficultySettings() {
        let expected: [(Difficulty, [MusicalRole], Float, TimeInterval, Double, Int)] = [
            (.heaven, [.drum, .melody], 0.45, 0.25, 2.4, 2),
            (.easy, [.drum, .bass, .melody], 0.35, 0.20, 4, 4),
            (.normal, [.drum, .bass, .melody, .vocal], 0.28, 0.125, 6, 4),
            (.hard, [.drum, .bass, .melody, .vocal, .accompaniment], 0.22, 0.125, 8.5, 8),
            (.hell, MusicalRole.allCases, 0.16, 0.125, 12, 8)
        ]

        for (difficulty, roles, confidence, sustain, nps, subdivision) in expected {
            let policy = AnalyzerConfiguration.default.policy(for: difficulty)
            XCTAssertEqual(policy.activeRoles, roles)
            XCTAssertEqual(policy.minimumConfidence, confidence)
            XCTAssertEqual(policy.minimumSustainDuration, sustain)
            XCTAssertEqual(policy.npsCap, nps)
            XCTAssertEqual(policy.subdivisionDenominator, subdivision)
        }
    }

    func testBeatTrackerProducesBeatPositionsAndDownbeats() throws {
        let frames = (0..<32).map { index in
            SpectralFrame(
                flux: index.isMultiple(of: 4) ? 2 : 0.05,
                bass: 0.8,
                mid: 0.2,
                treble: 0.1,
                centroid: 180,
                rms: 0.5,
                lowFlux: index.isMultiple(of: 4) ? 2 : 0.02,
                midFlux: 0.02,
                highFlux: 0.02
            )
        }
        let onsets = stride(from: 0.5, through: 7.5, by: 0.5).map {
            Onset(time: $0, strength: 1, bass: 0.8, mid: 0.2, treble: 0.1, centroid: 180)
        }
        let input = AnalyzerInput(
            frames: frames,
            onsets: onsets,
            duration: 8,
            sampleRate: 4,
            hopSize: 1,
            tempo: 120,
            configuration: .default
        )

        let grid = try DSPBeatTracker().track(input)

        XCTAssertGreaterThanOrEqual(grid.beats.count, 12)
        XCTAssertGreaterThanOrEqual(grid.downbeats.count, 2)
        XCTAssertEqual(grid.beats.first?.beatInBar, 0)
        XCTAssertTrue(grid.beats.contains { $0.barIndex == 1 && $0.beatInBar == 0 })
        XCTAssertGreaterThan(grid.confidence, 0)
    }

    func testSectionAnalyzerFindsEnergyChangeAndPhraseBoundaries() throws {
        let frames = (0..<64).map { index in
            let energy: Float = index < 32 ? 0.15 : 0.9
            return SpectralFrame(
                flux: index.isMultiple(of: 4) ? energy : 0.02,
                bass: energy,
                mid: energy,
                treble: energy,
                centroid: index < 32 ? 220 : 1_200,
                rms: energy
            )
        }
        let input = AnalyzerInput(
            frames: frames,
            onsets: [],
            duration: 16,
            sampleRate: 4,
            hopSize: 1,
            tempo: 120,
            configuration: .default,
            beatGrid: BeatGrid(
                tempo: 120,
                beats: (0..<32).map { BeatPosition(index: $0, time: Double($0) * 0.5, barIndex: $0 / 4, beatInBar: $0 % 4, confidence: 1) },
                downbeats: [0, 2, 4, 6, 8, 10, 12, 14],
                confidence: 1
            )
        )

        let result = try DSPSectionAnalyzer().analyze(input)

        XCTAssertGreaterThanOrEqual(result.sections.count, 2)
        XCTAssertTrue(result.sections.dropFirst().contains { abs($0.startTime - 8) <= 1 })
        XCTAssertFalse(result.phrases.isEmpty)
    }

    func testHarmonicPercussiveSeparatorDistinguishesTransientAndStableFrames() throws {
        let input = AnalyzerInput(
            frames: [
                SpectralFrame(flux: 4, bass: 0.4, mid: 0.2, treble: 0.1, centroid: 180, rms: 0.5),
                SpectralFrame(flux: 0.02, bass: 0.4, mid: 0.2, treble: 0.1, centroid: 440, rms: 0.5)
            ],
            onsets: [],
            duration: 1,
            sampleRate: 2,
            hopSize: 1,
            tempo: 120,
            configuration: .default
        )

        let frames = try DSPHarmonicPercussiveSeparator().separate(input)

        XCTAssertGreaterThan(frames[0].percussiveEnergy, frames[1].percussiveEnergy)
        XCTAssertGreaterThan(frames[1].harmonicEnergy, frames[0].harmonicEnergy)
    }

    func testDrumAnalyzerClassifiesKickSnareAndHihat() throws {
        let frames = (0..<12).map { index in
            SpectralFrame(
                flux: 1,
                bass: 0.4,
                mid: 0.3,
                treble: 0.2,
                centroid: 400,
                rms: 0.5,
                lowFlux: index == 2 ? 2 : 0.01,
                midFlux: index == 6 ? 2 : 0.01,
                highFlux: index == 10 ? 2 : 0.01
            )
        }
        let input = AnalyzerInput(
            frames: frames,
            onsets: [],
            duration: 12,
            sampleRate: 1,
            hopSize: 1,
            tempo: 120,
            configuration: .default
        )

        let events = try DSPDrumEventDetector().detect(input)

        XCTAssertTrue(events.contains { $0.kind == .kick })
        XCTAssertTrue(events.contains { $0.kind == .snare })
        XCTAssertTrue(events.contains { $0.kind == .hihatLike })
    }

    func testMelodyAndBassTrackIndependentContours() throws {
        let frames = (0..<8).map { index in
            SpectralFrame(
                flux: 0.1,
                bass: index < 4 ? 0.8 : 0.1,
                mid: 0.6,
                treble: 0.2,
                centroid: index < 4 ? 110 : 440,
                rms: 0.5,
                dominantFrequency: index < 4 ? 110 : 440,
                pitchConfidence: 0.9
            )
        }
        let input = AnalyzerInput(
            frames: frames,
            onsets: [],
            duration: 4,
            sampleRate: 2,
            hopSize: 1,
            tempo: 120,
            configuration: .default
        )

        let melody = try DSPMelodyTracker().track(input)
        let bass = try DSPBassTracker().track(input)

        XCTAssertFalse(melody.contour.isEmpty)
        XCTAssertFalse(bass.contour.isEmpty)
        XCTAssertTrue(melody.objects.allSatisfy { $0.sourceRole == .melody })
        XCTAssertTrue(bass.objects.allSatisfy { $0.sourceRole == .bass })
    }

    func testSustainExtractionRejectsPercussiveObjectsAndScoresStableContour() {
        let objects = [
            MusicalObject(
                id: 1,
                onsetTime: 3,
                offsetTime: 4.5,
                sourceRole: .melody,
                meanEnergy: 0.8,
                sustainStability: 0.9,
                percussiveness: 0.1,
                pitchContour: [ContourPoint(time: 3, value: 440, confidence: 0.9), ContourPoint(time: 4.5, value: 494, confidence: 0.9)],
                centroidContour: [],
                voicingConfidence: 0.9,
                confidence: 0.9,
                importanceScore: 0.8
            ),
            MusicalObject(
                id: 2,
                onsetTime: 5,
                offsetTime: 5.1,
                sourceRole: .drum,
                meanEnergy: 0.9,
                sustainStability: 0.1,
                percussiveness: 0.95,
                pitchContour: [],
                centroidContour: [],
                voicingConfidence: 0,
                confidence: 0.9,
                importanceScore: 0.9
            )
        ]

        let candidates = SustainCandidateExtractor.extract(
            objects: objects,
            beatGrid: .empty(tempo: 120),
            sections: [],
            phrases: [],
            configuration: .default
        )

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].sourceRole, .melody)
        XCTAssertGreaterThan(candidates[0].sustainScore, 0.5)
        XCTAssertEqual(candidates[0].duration, 1.5, accuracy: 1e-9)
    }

    func testDifficultySelectsAdditionalIndependentMusicLayers() {
        let objects = [
            makeObject(id: 1, time: 3.0, role: .drum),
            makeObject(id: 2, time: 3.5, role: .bass),
            makeObject(id: 3, time: 4.0, role: .melody),
            makeObject(id: 4, time: 4.5, role: .vocal),
            makeObject(id: 5, time: 5.0, role: .accompaniment)
        ]
        let analysis = AnalysisResult(
            duration: 8,
            tempo: 120,
            onsets: objects.map { Onset(time: $0.onsetTime, strength: 1, bass: 0.4, mid: 0.4, treble: 0.4, centroid: 440) },
            meanBass: 0.4,
            meanMid: 0.4,
            meanTreble: 0.4,
            meanRMS: 0.5,
            musicalObjects: objects
        )

        let easy = MusicalEventAdapter.events(from: analysis, difficulty: .easy, configuration: .default)
        let hard = MusicalEventAdapter.events(from: analysis, difficulty: .hard, configuration: .default)

        XCTAssertTrue(easy.allSatisfy { [.drum, .bass, .melody].contains($0.sourceRole) })
        XCTAssertGreaterThan(hard.count, easy.count)
        XCTAssertTrue(hard.contains { $0.sourceRole == .vocal })
        XCTAssertTrue(hard.contains { $0.sourceRole == .accompaniment })
    }

    func testPipelineAssignsGloballyUniqueObjectIDsAcrossLongFrameRanges() {
        let frames = (0..<1_300).map { index in
            SpectralFrame(
                flux: 0.01,
                bass: 0.2,
                mid: 0.7,
                treble: 0.1,
                centroid: 440,
                rms: 0.5,
                dominantFrequency: index == 175 ? 160 : (index == 1_175 ? 440 : 0),
                pitchConfidence: index == 175 || index == 1_175 ? 0.9 : 0
            )
        }
        let input = AnalyzerInput(
            frames: frames,
            onsets: [],
            duration: 162.5,
            sampleRate: 8,
            hopSize: 1,
            tempo: 120,
            configuration: .default
        )

        let first = MIRAnalysisPipeline.analyze(input: input)
        let second = MIRAnalysisPipeline.analyze(input: input)
        let objectIDs = first.musicalObjects.map(\.id)
        let candidateIDs = first.sustainCandidates.map(\.objectID)

        XCTAssertEqual(first, second)
        XCTAssertTrue(first.sustainCandidates.contains { $0.sourceRole == .melody })
        XCTAssertTrue(first.sustainCandidates.contains { $0.sourceRole == .vocal })
        XCTAssertEqual(objectIDs.count, Set(objectIDs).count)
        XCTAssertEqual(candidateIDs.count, Set(candidateIDs).count)
    }

    func testEventAdapterKeepsHigherImportanceCandidateOnObjectIDCollision() throws {
        var object = makeObject(id: 1, time: 3, role: .melody)
        object.offsetTime = 3.5
        object.sustainStability = 0.8
        let candidate = try XCTUnwrap(
            SustainCandidateExtractor.extract(
                objects: [object],
                beatGrid: .empty(tempo: 120),
                sections: [],
                phrases: [],
                configuration: .default
            ).first
        )
        var higherImportance = candidate
        higherImportance.importanceScore = candidate.importanceScore + 0.1
        higherImportance.confidence = candidate.confidence + 0.05

        let analysis = AnalysisResult(
            duration: 8,
            tempo: 120,
            onsets: [],
            meanBass: 0.1,
            meanMid: 0.5,
            meanTreble: 0.1,
            meanRMS: 0.5,
            musicalObjects: [object],
            sustainCandidates: [candidate, higherImportance]
        )

        let events = MusicalEventAdapter.events(
            from: analysis,
            difficulty: .easy,
            configuration: .default
        )

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].sustainCandidate, higherImportance)
    }

    func testSustainedMIREventCrossingSafetyDelayGeneratesDrags() {
        let object = MusicalObject(
            id: 1,
            onsetTime: 0,
            offsetTime: 8,
            sourceRole: .melody,
            meanEnergy: 0.8,
            sustainStability: 0.9,
            percussiveness: 0.1,
            pitchContour: stride(from: 0.0, through: 8.0, by: 0.5).map {
                ContourPoint(time: $0, value: 220 + Float($0 * 8), confidence: 0.9)
            },
            centroidContour: [],
            voicingConfidence: 0.9,
            confidence: 0.9,
            importanceScore: 0.9
        )
        let analysis = AnalysisResult(
            duration: 8,
            tempo: 120,
            onsets: [],
            meanBass: 0.1,
            meanMid: 0.8,
            meanTreble: 0.1,
            meanRMS: 0.5,
            musicalObjects: [object],
            sustainCandidates: SustainCandidateExtractor.extract(
                objects: [object],
                beatGrid: .empty(tempo: 120),
                sections: [],
                phrases: [],
                configuration: .default
            )
        )

        for difficulty in [Difficulty.easy, .normal, .hard, .hell] {
            let beatmap = BeatmapGenerator.generate(from: analysis, difficulty: difficulty, seed: 42)
            XCTAssertTrue(
                beatmap.notes.contains { $0.kind == .drag },
                "Expected a sustained MIR drag for \(difficulty)"
            )
        }
    }

    func testContourDrivesSustainLanePathAndSeededGenerationIsStable() throws {
        let object = MusicalObject(
            id: 9,
            onsetTime: 3,
            offsetTime: 5,
            sourceRole: .melody,
            meanEnergy: 0.8,
            sustainStability: 0.8,
            percussiveness: 0.1,
            pitchContour: stride(from: 3.0, through: 5.0, by: 0.5).map {
                ContourPoint(time: $0, value: 220 + Float(($0 - 3) * 180), confidence: 0.9)
            },
            centroidContour: [],
            voicingConfidence: 0.9,
            confidence: 0.9,
            importanceScore: 1
        )
        let analysis = AnalysisResult(
            duration: 8,
            tempo: 120,
            onsets: [Onset(time: 3, strength: 1, bass: 0.2, mid: 0.8, treble: 0.2, centroid: 440)],
            meanBass: 0.2,
            meanMid: 0.8,
            meanTreble: 0.2,
            meanRMS: 0.5,
            musicalObjects: [object],
            sustainCandidates: SustainCandidateExtractor.extract(
                objects: [object],
                beatGrid: .empty(tempo: 120),
                sections: [],
                phrases: [],
                configuration: .default
            )
        )

        let first = BeatmapGenerator.generate(from: analysis, difficulty: .hell, seed: 42)
        let second = BeatmapGenerator.generate(from: analysis, difficulty: .hell, seed: 42)

        XCTAssertEqual(first, second)
        XCTAssertTrue(first.notes.contains { $0.kind == .drag && !$0.lanePath.isEmpty })
        XCTAssertTrue(first.notes.contains { $0.sourceRole == .melody })
    }

    func testVersionedAnalysisRejectsLegacyPayloadForReanalysisAndAcceptsCurrentPayload() throws {
        let legacy = """
        {"duration":8,"tempo":120,"onsets":[],"meanBass":0.1,"meanMid":0.2,"meanTreble":0.3,"meanRMS":0.4}
        """.data(using: .utf8)!
        XCTAssertNil(AnalysisViewModel.decodeStoredAnalysis(legacy))

        let current = try JSONEncoder().encode(
            AnalysisResult(duration: 8, tempo: 120, onsets: [], meanBass: 0.1, meanMid: 0.2, meanTreble: 0.3, meanRMS: 0.4)
        )
        XCTAssertEqual(AnalysisViewModel.decodeStoredAnalysis(current)?.schemaVersion, AnalysisResult.currentSchemaVersion)
    }

    func testDebugJSONIncludesAnalysisSelectionAndFinalNoteSources() throws {
        let analysis = AnalysisResult(
            duration: 8,
            tempo: 120,
            onsets: [Onset(time: 3, strength: 1, bass: 1, mid: 0.1, treble: 0.1, centroid: 180)],
            meanBass: 0.5,
            meanMid: 0.2,
            meanTreble: 0.2,
            meanRMS: 0.5,
            musicalObjects: [makeObject(id: 1, time: 3, role: .drum)]
        )
        let beatmap = BeatmapGenerator.generate(from: analysis, difficulty: .easy, seed: 42)

        let data = try DebugJSONExporter.export(analysis: analysis, beatmaps: [beatmap])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertNotNil(json["analyzerBackend"])
        XCTAssertNotNil(json["configuration"])
        XCTAssertNotNil(json["beats"])
        XCTAssertNotNil(json["sections"])
        XCTAssertNotNil(json["extractedMusicalObjects"])
        XCTAssertNotNil(json["sustainCandidates"])
        XCTAssertNotNil(json["excludedReasons"])
        XCTAssertNotNil(json["finalNotes"])
        XCTAssertNotNil(json["difficultyStatistics"])
    }

    private func makeObject(id: Int, time: TimeInterval, role: MusicalRole) -> MusicalObject {
        MusicalObject(
            id: id,
            onsetTime: time,
            offsetTime: time + 0.1,
            sourceRole: role,
            meanEnergy: 0.8,
            sustainStability: 0.2,
            percussiveness: role == .drum ? 0.9 : 0.2,
            pitchContour: [],
            centroidContour: [ContourPoint(time: time, value: 440, confidence: 0.8)],
            voicingConfidence: role == .vocal ? 0.8 : 0.2,
            confidence: 0.9,
            importanceScore: 0.8
        )
    }
}
