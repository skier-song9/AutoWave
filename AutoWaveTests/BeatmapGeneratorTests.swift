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

    func testThemeSelectionUsesDominanceTempoAndNearTieRule() {
        XCTAssertEqual(
            GameTheme.select(
                tempo: 129,
                meanBass: 0.8,
                meanMid: 0.2,
                meanTreble: 0.1,
                meanRMS: 0.5
            ).id,
            "deepSea"
        )
        XCTAssertEqual(
            GameTheme.select(
                tempo: 130,
                meanBass: 0.8,
                meanMid: 0.2,
                meanTreble: 0.1,
                meanRMS: 0.5
            ).id,
            "neonRush"
        )
        XCTAssertEqual(
            GameTheme.select(
                tempo: 120,
                meanBass: 0.2,
                meanMid: 0.8,
                meanTreble: 0.1,
                meanRMS: 0.5
            ).id,
            "tide"
        )
        XCTAssertEqual(
            GameTheme.select(
                tempo: 120,
                meanBass: 0.2,
                meanMid: 0.1,
                meanTreble: 0.8,
                meanRMS: 0.5
            ).id,
            "dawn"
        )
        XCTAssertEqual(
            GameTheme.select(
                tempo: 180,
                meanBass: 0.8,
                meanMid: 0.75,
                meanTreble: 0.1,
                meanRMS: 0.5
            ).id,
            "prism"
        )
    }

    func testThemePresetsExposeExactDesignTokens() throws {
        XCTAssertEqual(GameTheme.presets.count, 5)

        let deepSea = try XCTUnwrap(GameTheme.presets.first { $0.id == "deepSea" })
        XCTAssertEqual(deepSea.displayName, "심해")
        XCTAssertEqual(deepSea.backgroundTop, RGB(hex: 0x070B26))
        XCTAssertEqual(deepSea.backgroundBottom, RGB(hex: 0x17103F))
        XCTAssertEqual(deepSea.tapNote, RGB(hex: 0x4FC3F7))
        XCTAssertEqual(deepSea.tapNoteStroke, RGB(hex: 0xFFFFFF))
        XCTAssertEqual(deepSea.dragBody, RGB(hex: 0x7E57C2))
        XCTAssertEqual(deepSea.dragCap, RGB(hex: 0xB39DDB))
        XCTAssertEqual(deepSea.ripple, RGB(hex: 0x283593))
        XCTAssertEqual(deepSea.judgmentAccent, RGB(hex: 0xFFD54F))
        XCTAssertEqual(deepSea.laneLine, RGB(hex: 0x7986CB))

        let expectedIDs = ["deepSea", "neonRush", "tide", "dawn", "prism"]
        XCTAssertEqual(GameTheme.presets.map(\.id), expectedIDs)
    }

    func testGeneratorStoresSelectedThemeAndVersion() {
        let analysis = AnalysisResult(
            duration: 10,
            tempo: 140,
            onsets: [],
            meanBass: 0.8,
            meanMid: 0.2,
            meanTreble: 0.1,
            meanRMS: 0.5
        )

        let beatmap = BeatmapGenerator.generate(from: analysis, difficulty: .normal, seed: 42)

        XCTAssertEqual(beatmap.themeID, "neonRush")
        XCTAssertEqual(beatmap.generatorVersion, 2)
        XCTAssertEqual(beatmap.palette, beatmapThemePalette(for: GameTheme.presets[1]))
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

    func testPaletteUsesSelectedThemeTapColor() {
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
        XCTAssertEqual(palette, GameTheme.preset(id: "deepSea").themePalette)
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

    private func beatmapThemePalette(for theme: GameTheme) -> ThemePalette {
        let color = theme.tapNote
        let maximum = max(color.r, max(color.g, color.b))
        let minimum = min(color.r, min(color.g, color.b))
        let range = maximum - minimum
        let brightness = maximum
        let saturation = maximum == 0 ? 0 : range / maximum
        let hue: Double
        if range == 0 {
            hue = 0
        } else if maximum == color.r {
            hue = ((color.g - color.b) / range).truncatingRemainder(dividingBy: 6) / 6
        } else if maximum == color.g {
            hue = ((color.b - color.r) / range + 2) / 6
        } else {
            hue = ((color.r - color.g) / range + 4) / 6
        }

        return ThemePalette(
            hue: hue >= 0 ? hue : hue + 1,
            saturation: saturation,
            brightness: brightness
        )
    }
}
