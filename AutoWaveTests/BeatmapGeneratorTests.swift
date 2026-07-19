import Foundation
import XCTest
@testable import AutoWave

final class BeatmapGeneratorTests: XCTestCase {
    func testDifficultyProfilesMatchSpecification() {
        let expected: [(Difficulty, Int, Double, Double, Int, Double, Double, Double)] = [
            (.heaven, 4, 1.2, 80, 1, 0.10, 0.0, 220),
            (.easy, 4, 2.4, 60, 1, 0.15, 0.2, 280),
            (.normal, 5, 4.0, 40, 2, 0.20, 0.4, 360),
            (.hard, 6, 6.5, 20, 2, 0.25, 0.6, 440),
            (.hell, 7, 9.5, 8, 3, 0.30, 0.8, 545)
        ]

        for (difficulty, laneCount, rate, percentile, simultaneous, drag, moving, scroll) in expected {
            let profile = DifficultyProfile.profile(for: difficulty)
            XCTAssertEqual(profile.laneCount, laneCount)
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
            XCTAssertEqual(beatmap.laneCount, DifficultyProfile.profile(for: difficulty).laneCount)

            for note in beatmap.notes {
                XCTAssertGreaterThanOrEqual(note.time, BeatmapGenerator.minimumPlayableNoteTime)
                XCTAssertGreaterThanOrEqual(note.lane, 0)
                XCTAssertLessThan(note.lane, Double(beatmap.laneCount))
                for keyframe in note.lanePath {
                    XCTAssertGreaterThanOrEqual(keyframe.lane, 0)
                    XCTAssertLessThan(keyframe.lane, Double(beatmap.laneCount))
                }
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

                    let minimumGap = difficulty == .heaven || difficulty == .easy ? 0.25 : 0.12
                    XCTAssertGreaterThanOrEqual(
                        pair.1.time - previous.time,
                        minimumGap - 1e-9
                    )
                }
            }
        }
    }

    func testGeneratedNotesStartAfterSafetyDelay() {
        let analysis = AnalysisResult(
            duration: 8,
            tempo: 120,
            onsets: [
                Onset(time: 0.25, strength: 1, bass: 1, mid: 0.2, treble: 0.1, centroid: 200),
                Onset(time: 2.5, strength: 0.9, bass: 0.8, mid: 0.2, treble: 0.1, centroid: 300),
                Onset(time: 3.5, strength: 1, bass: 0.7, mid: 0.2, treble: 0.1, centroid: 400)
            ],
            meanBass: 0.8,
            meanMid: 0.2,
            meanTreble: 0.1,
            meanRMS: 0.5
        )

        let beatmap = BeatmapGenerator.generate(from: analysis, difficulty: .easy, seed: 42)

        XCTAssertTrue(beatmap.notes.allSatisfy {
            $0.time >= BeatmapGenerator.minimumPlayableNoteTime
        })
        XCTAssertTrue(beatmap.notes.contains { $0.time >= 3.0 })
    }

    func testLateOnsetsAreNotSuppressedByLoudIntro() {
        let onsets = (0..<8).map { index in
            Onset(
                time: 0.25 + Double(index) * 0.25,
                strength: 1,
                bass: 0.8,
                mid: 0.2,
                treble: 0.1,
                centroid: 300
            )
        } + [
            Onset(time: 4.0, strength: 0.35, bass: 0.4, mid: 0.3, treble: 0.2, centroid: 900),
            Onset(time: 4.5, strength: 0.3, bass: 0.4, mid: 0.3, treble: 0.2, centroid: 1_000)
        ]
        let analysis = AnalysisResult(
            duration: 8,
            tempo: 120,
            onsets: onsets,
            meanBass: 0.5,
            meanMid: 0.3,
            meanTreble: 0.2,
            meanRMS: 0.5
        )

        let beatmap = BeatmapGenerator.generate(from: analysis, difficulty: .easy, seed: 42)

        XCTAssertTrue(beatmap.notes.contains { $0.time >= 4.0 })
    }

    func testAudibleTrackWithNoDetectedOnsetsGetsSparseBeatFallback() {
        let analysis = AnalysisResult(
            duration: 8,
            tempo: 120,
            onsets: [],
            meanBass: 0.4,
            meanMid: 0.3,
            meanTreble: 0.2,
            meanRMS: 0.5
        )

        let beatmap = BeatmapGenerator.generate(from: analysis, difficulty: .normal, seed: 42)

        XCTAssertFalse(beatmap.notes.isEmpty)
        XCTAssertTrue(beatmap.notes.allSatisfy {
            $0.time >= BeatmapGenerator.minimumPlayableNoteTime
        })
    }

    func testBeatSnappingPreservesDetectedBeatPhase() {
        let analysis = AnalysisResult(
            duration: 8,
            tempo: 120,
            onsets: [
                Onset(time: 3.125, strength: 1, bass: 0.8, mid: 0.2, treble: 0.1, centroid: 300),
                Onset(time: 3.625, strength: 1, bass: 0.8, mid: 0.2, treble: 0.1, centroid: 300),
                Onset(time: 4.125, strength: 1, bass: 0.9, mid: 0.2, treble: 0.1, centroid: 300)
            ],
            meanBass: 0.8,
            meanMid: 0.2,
            meanTreble: 0.1,
            meanRMS: 0.5
        )

        let notes = BeatmapGenerator.generate(from: analysis, difficulty: .easy, seed: 42).notes

        XCTAssertTrue(notes.contains { abs($0.time - 3.125) < 1e-9 })
        XCTAssertTrue(notes.contains { abs($0.time - 3.625) < 1e-9 })
    }

    func testGeneratorDoesNotFillUnsupportedGridSlots() {
        let analysis = AnalysisResult(
            duration: 10,
            tempo: 120,
            onsets: [
                Onset(time: 3.25, strength: 1, bass: 0.8, mid: 0.2, treble: 0.1, centroid: 300),
                Onset(time: 5.25, strength: 0.9, bass: 0.8, mid: 0.2, treble: 0.1, centroid: 500)
            ],
            meanBass: 0.8,
            meanMid: 0.2,
            meanTreble: 0.1,
            meanRMS: 0.5
        )

        let beatmap = BeatmapGenerator.generate(from: analysis, difficulty: .normal, seed: 42)

        XCTAssertLessThanOrEqual(beatmap.notes.count, analysis.onsets.count)
        XCTAssertFalse(beatmap.notes.contains { abs($0.time - 4.0) < 1e-9 })
    }

    func testSequentialNotesHaveAtLeastNinetyMillisecondsAddedSpacing() {
        let minimumGap: TimeInterval = 0.09

        for difficulty in Difficulty.allCases {
            let notes = BeatmapGenerator.generate(
                from: makeBusyAnalysis(),
                difficulty: difficulty,
                seed: 42
            ).notes.sorted { $0.time < $1.time }
            let distinctTimes = notes.map(\.time).reduce(into: [TimeInterval]()) { result, time in
                if result.last.map({ abs($0 - time) > 1e-9 }) ?? true {
                    result.append(time)
                }
            }

            for pair in zip(distinctTimes, distinctTimes.dropFirst()) {
                XCTAssertGreaterThanOrEqual(pair.1 - pair.0, minimumGap - 1e-9)
            }
        }
    }

    func testNearSilentTrackGetsBeatGridFallbackAtHalfNotePerSecond() {
        let duration = 60.0
        let analysis = AnalysisResult(
            duration: duration,
            tempo: 120,
            onsets: [],
            meanBass: 0.0001,
            meanMid: 0.0001,
            meanTreble: 0.0001,
            meanRMS: 0.0001,
            intensityCurve: Array(repeating: 0, count: Int(duration))
        )

        let beatmap = BeatmapGenerator.generate(from: analysis, difficulty: .normal, seed: 42)

        XCTAssertGreaterThanOrEqual(Double(beatmap.notes.count) / duration, 0.5)
        XCTAssertGreaterThanOrEqual(beatmap.notes.first?.time ?? 0, 3.0)
    }

    func testIntensityCurveIncreasesSecondHalfDensity() {
        let onsets = stride(from: 3.0, through: 59.75, by: 0.25).map { time in
            Onset(
                time: time,
                strength: 0.6,
                bass: 0.2,
                mid: 0.8,
                treble: 0.1,
                centroid: 900
            )
        }
        let analysis = AnalysisResult(
            duration: 60,
            tempo: 120,
            onsets: onsets,
            meanBass: 0.2,
            meanMid: 0.8,
            meanTreble: 0.1,
            meanRMS: 0.4,
            intensityCurve: Array(repeating: 0.05, count: 30)
                + Array(repeating: 0.95, count: 30)
        )

        let notes = BeatmapGenerator.generate(from: analysis, difficulty: .normal, seed: 42).notes
        let quietCount = notes.filter { $0.time < 31 }.count
        let loudCount = notes.filter { $0.time >= 31 }.count

        XCTAssertGreaterThan(loudCount, quietCount)
    }

    func testUniformClicksAvoidThreeJacksAndThreeRepeatingFourLaneCycles() {
        let analysis = AnalysisResult(
            duration: 30,
            tempo: 120,
            onsets: stride(from: 3.0, through: 29.75, by: 0.25).map { time in
                Onset(
                    time: time,
                    strength: 1,
                    bass: 0.2,
                    mid: 0.8,
                    treble: 0.1,
                    centroid: 900
                )
            },
            meanBass: 0.2,
            meanMid: 0.8,
            meanTreble: 0.1,
            meanRMS: 0.4
        )

        let lanes = BeatmapGenerator.generate(from: analysis, difficulty: .normal, seed: 42)
            .notes
            .sorted { $0.time == $1.time ? $0.lane < $1.lane : $0.time < $1.time }
            .map { Int($0.lane.rounded()) }

        for windowStart in 0..<(max(0, lanes.count - 2)) {
            XCTAssertFalse(
                lanes[windowStart] == lanes[windowStart + 1]
                    && lanes[windowStart + 1] == lanes[windowStart + 2]
            )
        }

        guard lanes.count >= 12 else {
            XCTFail("Expected enough notes to inspect repeated patterns")
            return
        }
        for start in 0...(lanes.count - 12) {
            let first = Array(lanes[start..<(start + 4)])
            let second = Array(lanes[(start + 4)..<(start + 8)])
            let third = Array(lanes[(start + 8)..<(start + 12)])
            XCTAssertFalse(first == second && second == third)
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
        XCTAssertEqual(beatmap.generatorVersion, 6)
        XCTAssertEqual(beatmap.palette, beatmapThemePalette(for: GameTheme.presets[1]))
    }

    func testHellContainsMovingDrag() {
        let beatmap = BeatmapGenerator.generate(from: makeBusyAnalysis(), difficulty: .hell, seed: 42)

        XCTAssertTrue(beatmap.notes.contains { $0.kind == .drag && !$0.lanePath.isEmpty })
    }

    func testMovingDragKeyframesShiftOneLaneAndStaySpaced() {
        let analysis = makeBusyAnalysis()

        for difficulty in Difficulty.allCases {
            for seed in 0..<10 {
                let beatmap = BeatmapGenerator.generate(
                    from: analysis,
                    difficulty: difficulty,
                    seed: UInt64(seed)
                )

                for note in beatmap.notes where note.kind == .drag && !note.lanePath.isEmpty {
                    var previousLane = note.lane
                    var previousOffset = 0.0
                    for keyframe in note.lanePath {
                        XCTAssertLessThanOrEqual(
                            abs(keyframe.lane - previousLane),
                            1.0 + 1e-9,
                            "(difficulty) seed (seed) has a multi-lane step"
                        )
                        XCTAssertGreaterThanOrEqual(
                            keyframe.offset - previousOffset,
                            0.3 - 1e-9,
                            "(difficulty) seed (seed) has a short drag step"
                        )
                        previousLane = keyframe.lane
                        previousOffset = keyframe.offset
                    }
                }
            }
        }
    }

    func testHellHasChordsAndMoreNotesThanHardByMeaningfulRatio() {
        let analysis = makeBusyAnalysis()
        let hard = BeatmapGenerator.generate(from: analysis, difficulty: .hard, seed: 42)
        let hell = BeatmapGenerator.generate(from: analysis, difficulty: .hell, seed: 42)
        let grouped = Dictionary(grouping: hell.notes) { Int(($0.time * 1_000_000).rounded()) }

        XCTAssertGreaterThan(Double(hell.notes.count), Double(hard.notes.count) * 1.15)
        XCTAssertTrue(grouped.values.contains { $0.count == 2 })
    }

    func testSimultaneityCapIsAppliedPerDifficulty() {
        let analysis = makeBusyAnalysis()

        for difficulty in Difficulty.allCases {
            let beatmap = BeatmapGenerator.generate(from: analysis, difficulty: difficulty, seed: 42)
            let grouped = Dictionary(grouping: beatmap.notes) { Int(($0.time * 1_000_000).rounded()) }
            let cap = DifficultyProfile.profile(for: difficulty).maxSimultaneous

            XCTAssertTrue(grouped.values.allSatisfy { $0.count <= cap }, "\(difficulty) exceeds \(cap)")
        }
    }

    func testHellReachesThreeSimultaneousNotesWithoutExceedingCap() {
        let beatmap = BeatmapGenerator.generate(from: makeBusyAnalysis(), difficulty: .hell, seed: 42)
        let grouped = Dictionary(grouping: beatmap.notes) { Int(($0.time * 1_000_000).rounded()) }

        XCTAssertTrue(grouped.values.contains { $0.count == 3 })
        XCTAssertTrue(grouped.values.allSatisfy { $0.count <= 3 })
    }

    func testNoDifficultyHasMoreThanTwoConcurrentDragNotes() {
        let analysis = makeBusyAnalysis()

        for difficulty in Difficulty.allCases {
            let beatmap = BeatmapGenerator.generate(from: analysis, difficulty: difficulty, seed: 42)
            XCTAssertLessThanOrEqual(
                maximumConcurrentDragCount(in: beatmap),
                2,
                "\(difficulty) has more than two concurrent drags"
            )
        }
    }

    func testNotesSnapToDifficultyBeatGrid() {
        let analysis = makeBusyAnalysis()
        let beat = 60 / analysis.tempo

        for difficulty in Difficulty.allCases {
            let beatmap = BeatmapGenerator.generate(from: analysis, difficulty: difficulty, seed: 42)
            let subdivision = difficulty == .heaven || difficulty == .easy
                ? beat / 2
                : difficulty == .normal ? beat / 4 : beat / 8

            for note in beatmap.notes {
                let gridPosition = note.time / subdivision
                XCTAssertEqual(gridPosition, gridPosition.rounded(), accuracy: 1e-7)
            }
        }
    }

    func testDragSpanExcludesTapsAcrossAllDifficultiesAndSeeds() {
        let analysis = makeBusyAnalysis()

        for difficulty in Difficulty.allCases {
            for seed in 0..<10 {
                let beatmap = BeatmapGenerator.generate(
                    from: analysis,
                    difficulty: difficulty,
                    seed: UInt64(seed)
                )

                for drag in beatmap.notes where drag.kind == .drag {
                    let dragLanes = [drag.lane] + drag.lanePath.map(\.lane)
                    let minimumLane = floor(dragLanes.min()!)
                    let maximumLane = ceil(dragLanes.max()!)
                    let dragStart = drag.time - 0.15
                    let dragEnd = drag.time + drag.duration + 0.15

                    for tap in beatmap.notes where tap.kind == .tap {
                        guard tap.time >= dragStart - 1e-9,
                              tap.time <= dragEnd + 1e-9 else { continue }
                        XCTAssertTrue(
                            tap.lane < minimumLane || tap.lane > maximumLane,
                            "Tap \(tap) conflicts with \(difficulty) drag \(drag), seed \(seed)"
                        )
                    }
                }
            }
        }
    }

    func testSpectralContentMapsLowToLeftAndHighToRight() {
        let onsets = [
            Onset(time: 3.5, strength: 1, bass: 1, mid: 0.1, treble: 0.05, centroid: 180),
            Onset(time: 5.0, strength: 1, bass: 0.05, mid: 0.1, treble: 1, centroid: 8_000)
        ]
        let analysis = AnalysisResult(
            duration: 6,
            tempo: 120,
            onsets: onsets,
            meanBass: 0.5,
            meanMid: 0.1,
            meanTreble: 0.5,
            meanRMS: 0.5
        )

        let notes = BeatmapGenerator.generate(from: analysis, difficulty: .easy, seed: 42).notes
        let lowLane = notes.first { $0.time < 4 }!.lane
        let highLane = notes.first { $0.time > 4 }!.lane

        XCTAssertLessThan(lowLane, highLane)
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

    private func maximumConcurrentDragCount(in beatmap: Beatmap) -> Int {
        let drags = beatmap.notes.filter { $0.kind == .drag }
        let checkpoints = drags.flatMap { [$0.time, $0.time + $0.duration] }

        return checkpoints.map { time in
            drags.filter { drag in
                drag.time <= time + 1e-9
                    && time < drag.time + drag.duration - 1e-9
            }.count
        }.max() ?? 0
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
