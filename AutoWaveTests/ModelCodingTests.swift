import Foundation
import SwiftData
import XCTest
@testable import AutoWave

final class ModelCodingTests: XCTestCase {
    func testBeatmapJSONRoundTripPreservesValue() throws {
        let noteID = UUID(uuidString: "4C7A6A5D-9E2D-4E4C-9BD4-7E5C7A8D6F1B")!
        let original = Beatmap(
            difficulty: .hard,
            tempo: 128,
            notes: [
                Note(
                    id: noteID,
                    kind: .drag,
                    time: 1.25,
                    lane: 1.5,
                    duration: 0.75,
                    lanePath: [LaneKeyframe(offset: 0.25, lane: 2.0)]
                )
            ],
            palette: ThemePalette(hue: 0.5, saturation: 0.7, brightness: 0.65),
            generatorVersion: 1,
            laneCount: 6
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Beatmap.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func testBeatmapDecodesDeepSeaForJSONWithoutThemeID() throws {
        let oldJSON = """
        {
          "difficulty": "normal",
          "tempo": 120,
          "notes": [],
          "palette": {
            "hue": 0.5,
            "saturation": 0.6,
            "brightness": 0.7
          },
          "generatorVersion": 1
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(Beatmap.self, from: oldJSON)

        XCTAssertEqual(decoded.themeID, "deepSea")
        XCTAssertEqual(decoded.laneCount, 4)
    }

    func testAnalysisResultJSONRoundTripPreservesOnsets() throws {
        let original = AnalysisResult(
            duration: 18.5,
            tempo: 132,
            onsets: [
                Onset(
                    time: 3.25,
                    strength: 0.8,
                    bass: 0.7,
                    mid: 0.2,
                    treble: 0.1,
                    centroid: 240,
                    band: .low
                ),
                Onset(
                    time: 4.0,
                    strength: 0.6,
                    bass: 0.1,
                    mid: 0.3,
                    treble: 0.8,
                    centroid: 3_200,
                    band: .high
                )
            ],
            meanBass: 0.4,
            meanMid: 0.3,
            meanTreble: 0.2,
            meanRMS: 0.5,
            intensityCurve: [0.1, 0.4, 0.9]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(AnalysisResult.self, from: data)

        XCTAssertEqual(try encoder.encode(decoded), data)
    }

    func testInMemoryModelContainerFetchesTrackAndBeatmap() throws {
        let schema = Schema([TrackEntity.self, BeatmapEntity.self, ScoreRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let track = TrackEntity(
            title: "Test track",
            sourceFilename: "test.m4a",
            importedAt: Date(timeIntervalSince1970: 0),
            relativeAudioPath: "AudioFiles/test.m4a"
        )
        let beatmapData = try JSONEncoder().encode(
            Beatmap(
                difficulty: .normal,
                tempo: 120,
                notes: [],
                palette: ThemePalette(hue: 0.5, saturation: 0.6, brightness: 0.7),
                generatorVersion: 1
            )
        )
        let beatmap = BeatmapEntity(
            difficulty: Difficulty.normal.rawValue,
            beatmapData: beatmapData,
            track: track
        )

        context.insert(track)
        context.insert(beatmap)
        try context.save()

        let descriptor = FetchDescriptor<TrackEntity>(
            predicate: #Predicate { $0.title == "Test track" }
        )
        let fetchedTracks = try context.fetch(descriptor)

        XCTAssertEqual(fetchedTracks.count, 1)
        XCTAssertEqual(fetchedTracks.first?.beatmaps.count, 1)
        XCTAssertEqual(fetchedTracks.first?.beatmaps.first?.difficulty, Difficulty.normal.rawValue)
        XCTAssertEqual(fetchedTracks.first?.beatmaps.first?.beatmapData, beatmapData)
    }
}
