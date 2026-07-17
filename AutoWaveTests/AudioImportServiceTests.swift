import AVFoundation
import Foundation
import SwiftData
import XCTest
@testable import AutoWave

@MainActor
final class AudioImportServiceTests: XCTestCase {
    func testImportCopiesAudioAndPersistsTrackMetadata() async throws {
        let fixtureURL = try makeWAVFixture(named: "Sample Song.wav")
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let context = try makeInMemoryContext()
        let track = try await AudioImportService.importAudio(from: fixtureURL, into: context)
        defer { try? FileManager.default.removeItem(at: track.audioURL) }

        XCTAssertEqual(track.title, "Sample Song")
        XCTAssertEqual(track.sourceFilename, "Sample Song.wav")
        XCTAssertEqual(track.relativeAudioPath.split(separator: "/").first, "AudioFiles")
        XCTAssertTrue(track.relativeAudioPath.hasSuffix(".wav"))
        XCTAssertNotNil(UUID(uuidString: URL(fileURLWithPath: track.relativeAudioPath).deletingPathExtension().lastPathComponent))
        XCTAssertGreaterThan(track.duration, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: track.audioURL.path))
    }

    func testImportUsesUniqueUUIDBasedNamesForSameSourceFile() async throws {
        let fixtureURL = try makeWAVFixture(named: "Repeated.wav")
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let context = try makeInMemoryContext()
        let firstTrack = try await AudioImportService.importAudio(from: fixtureURL, into: context)
        let secondTrack = try await AudioImportService.importAudio(from: fixtureURL, into: context)
        defer {
            try? FileManager.default.removeItem(at: firstTrack.audioURL)
            try? FileManager.default.removeItem(at: secondTrack.audioURL)
        }

        XCTAssertNotEqual(firstTrack.relativeAudioPath, secondTrack.relativeAudioPath)
        XCTAssertNotEqual(firstTrack.audioURL, secondTrack.audioURL)
        XCTAssertNotNil(UUID(uuidString: URL(fileURLWithPath: firstTrack.relativeAudioPath).deletingPathExtension().lastPathComponent))
        XCTAssertNotNil(UUID(uuidString: URL(fileURLWithPath: secondTrack.relativeAudioPath).deletingPathExtension().lastPathComponent))
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstTrack.audioURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondTrack.audioURL.path))
    }

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([TrackEntity.self, BeatmapEntity.self, ScoreRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    private func makeWAVFixture(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frameCount = AVAudioFrameCount(format.sampleRate * 0.25)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        for frame in 0..<Int(frameCount) {
            buffer.floatChannelData![0][frame] = sin(Float(frame) * 0.1) * 0.1
        }
        try file.write(from: buffer)

        let namedURL = url.deletingLastPathComponent().appendingPathComponent(name)
        try FileManager.default.moveItem(at: url, to: namedURL)
        return namedURL
    }
}
