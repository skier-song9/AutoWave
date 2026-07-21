import Foundation
import SwiftData
import XCTest
@testable import AutoWave

@MainActor
final class TrackDeletionServiceTests: XCTestCase {
    func testDeleteRemovesTrackCascadesBeatmapsAndRemovesAudioFile() throws {
        let context = try makeInMemoryContext()
        let track = makeTrack(in: context)
        context.insert(
            BeatmapEntity(
                difficulty: Difficulty.normal.rawValue,
                beatmapData: Data([1, 2, 3]),
                track: track
            )
        )
        context.insert(
            BeatmapEntity(
                difficulty: Difficulty.hard.rawValue,
                beatmapData: Data([4, 5, 6]),
                track: track
            )
        )
        try context.save()

        let audioURL = track.audioURL
        try FileManager.default.createDirectory(
            at: audioURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([0x00]).write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        XCTAssertEqual(try context.fetch(FetchDescriptor<BeatmapEntity>()).count, 2)

        try TrackDeletionService.delete(track, in: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<TrackEntity>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<BeatmapEntity>()).count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: audioURL.path))
    }

    func testDeleteSucceedsWhenAudioFileIsAlreadyMissing() throws {
        let context = try makeInMemoryContext()
        let track = makeTrack(in: context)
        try context.save()

        let audioURL = track.audioURL
        XCTAssertFalse(FileManager.default.fileExists(atPath: audioURL.path))

        XCTAssertNoThrow(try TrackDeletionService.delete(track, in: context))
        XCTAssertEqual(try context.fetch(FetchDescriptor<TrackEntity>()).count, 0)
    }

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([TrackEntity.self, BeatmapEntity.self, ScoreRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    private func makeTrack(in context: ModelContext) -> TrackEntity {
        let track = TrackEntity(
            title: "Deleted Song",
            sourceFilename: "Deleted Song.wav",
            importedAt: Date(),
            relativeAudioPath: "AudioFiles/\(UUID().uuidString).wav",
            duration: 12
        )
        context.insert(track)
        return track
    }
}
