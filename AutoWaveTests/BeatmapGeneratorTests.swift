import Foundation
import XCTest
@testable import AutoWave

final class BeatmapGeneratorTests: XCTestCase {
    func testDifficultyProfilesMatchSpecification() {
        let expected: [(Difficulty, Double, Double, Int, Double, Double, Double)] = [
            (.heaven, 0.8, 85, 1, 0.10, 0.0, 250),
            (.easy, 1.5, 65, 1, 0.15, 0.2, 320),
            (.normal, 2.5, 45, 1, 0.20, 0.4, 400),
            (.hard, 4.0, 25, 2, 0.25, 0.6, 500),
            (.hell, 6.0, 10, 2, 0.30, 0.8, 620)
        ]

        for (difficulty, rate, percentile, simultaneous, drag, moving, scroll) in expected {
            let profile = DifficultyProfile.profile(for: difficulty)
            XCTAssertEqual(profile.maxNotesPerSecond, rate)
            XCTAssertEqual(profile.strengthPercentile, percentile)
            XCTAssertEqual(profile.maxSimultaneous, simultaneous)
            XCTAssertEqual(profile.dragRatio, drag)
            XCTAssertEqual(profile.movingDragRatio, moving)
            XCTAssertEqual(profile.scrollSpeed, scroll)
        }
    }

    func testSameInputAndSeedProducesByteIdenticalJSON() throws {
        let analysis = makeBusyAnalysis()
        let first = BeatmapGenerator.generate(from: analysis, difficulty: .normal, seed: 42)
        let second = BeatmapGenerator.generate(from: analysis, difficulty: .normal, seed: 42)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        XCTAssertEqual(try encoder.encode(first), try encoder.encode(second))
    }

    func testDifferentSeedsProduceDifferentNoteLayouts() {
        let analysis = makeBusyAnalysis()
        let first = BeatmapGenerator.generate(from: analysis, difficulty: .normal, seed: 1)
        let second = BeatmapGenerator.generate(from: analysis, difficulty: .normal, seed: 2)

        let firstLayout = first.notes.map { note in
            "\(note.kind.rawValue):\(note.time):\(note.lane):\(note.duration):\(note.lanePath)"
        }
        let secondLayout = second.notes.map { note in
            "\(note.kind.rawValue):\(note.time):\(note.lane):\(note.duration):\(note.lanePath)"
        }
        XCTAssertNotEqual(firstLayout, secondLayout)
    }

    func testNoteCountsStrictlyIncreaseWithDifficulty() {
        let analysis = makeBusyAnalysis()
        let counts = Difficulty.allCases.map {
            BeatmapGenerator.generate(from: analysis, difficulty: $0, seed: 42).notes.count
        }

        XCTAssertTrue(zip(counts, counts.dropFirst()).allSatisfy { $0 < $1 }, "Counts: \(counts)")
    }

    func testLanesAndPerLaneOverlapRuleHold() {
        let analysis = makeBusyAnalysis()

        for difficulty in Difficulty.allCases {
            let beatmap = BeatmapGenerator.generate(from: analysis, difficulty: difficulty, seed: 42)
            XCTAssertEqual(beatmap.tempo, analysis.tempo)
            XCTAssertEqual(beatmap.generatorVersion, BeatmapGenerator.version)

            for note in beatmap.notes {
                XCTAssertGreaterThanOrEqual(note.lane, 0)
                XCTAssertLessThanOrEqual(note.lane, 3)
                if note.kind == .drag {
                    XCTAssertGreaterThan(note.duration, 0)
                }
            }

            let notesByLane = Dictionary(grouping: beatmap.notes) { Int($0.lane.rounded()) }
            for notes in notesByLane.values {
                let sorted = notes.sorted { $0.time < $1.time }
                for pair in zip(sorted, sorted.dropFirst()) {
                    let previous = pair.0
                    let previousEnd = previous.time
                        + (previous.kind == .drag ? previous.duration + 0.15 : 0)
                    XCTAssertGreaterThanOrEqual(pair.1.time + 1e-9, previousEnd)
                }
            }
        }
    }

    func testHellContainsMovingDrag() {
        let beatmap = BeatmapGenerator.generate(from: makeBusyAnalysis(), difficulty: .hell, seed: 42)

        XCTAssertTrue(beatmap.notes.contains { $0.kind == .drag && !$0.lanePath.isEmpty })
    }

    func testOneSecondRateCapHoldsForEveryDifficulty() {
        let analysis = makeBusyAnalysis()

        for difficulty in Difficulty.allCases {
            let beatmap = BeatmapGenerator.generate(from: analysis, difficulty: difficulty, seed: 42)
            let cap = Int(ceil(DifficultyProfile.profile(for: difficulty).maxNotesPerSecond))
            let times = beatmap.notes.map(\.time).sorted()

            for start in times {
                let count = times.filter { $0 >= start - 1e-9 && $0 < start + 1 - 1e-9 }.count
                XCTAssertLessThanOrEqual(count, cap, "\(difficulty) exceeds cap in window at \(start)")
            }
        }
    }

    func testPaletteUsesBandDominanceAndRMS() {
        let analysis = AnalysisResult(
            duration: 10,
            tempo: 120,
            onsets: [],
            meanBass: 0.8,
            meanMid: 0.4,
            meanTreble: 0.1,
            meanRMS: 0.5
        )

        let palette = BeatmapGenerator.generate(from: analysis, difficulty: .normal, seed: 0).palette
        XCTAssertEqual(palette.hue, (0.8 * 0.72 + 0.4 * 0.50) / 1.2, accuracy: 1e-12)
        XCTAssertEqual(palette.saturation, 0.55 + 0.25 * ((0.8 - 0.1) / 0.8), accuracy: 1e-12)
        XCTAssertEqual(palette.brightness, 0.625, accuracy: 1e-12)
    }

    private func makeBusyAnalysis() -> AnalysisResult {
        let times = stride(from: 0.25, through: 119.75, by: 0.25)
            .filter { !($0 > 30 && $0 < 31) }
        let onsets = times.enumerated().map { index, time in
            let repeatingStrength = Float(index % 32) / 31
            let strength = time == 30 || time == 31 ? 1 : 0.2 + 0.8 * repeatingStrength
            return Onset(
                time: time,
                strength: strength,
                bass: 0.2 + Float(index % 5) * 0.05,
                mid: 0.4 + Float(index % 7) * 0.03,
                treble: 0.3 + Float(index % 3) * 0.04,
                centroid: 200 + Float(index % 80) * 95
            )
        }

        return AnalysisResult(
            duration: 120,
            tempo: 120,
            onsets: onsets,
            meanBass: 0.4,
            meanMid: 0.6,
            meanTreble: 0.3,
            meanRMS: 0.7
        )
    }
}
