import AVFoundation
import Foundation
import SwiftData
import XCTest
@testable import AutoWave

@MainActor
final class AnalysisViewModelTests: XCTestCase {
    func testGeneratorVersionFourEntityRequiresAutomaticRegeneration() throws {
        XCTAssertTrue(AnalysisViewModel.shouldRegenerate(storedGeneratorVersions: [4]))
        XCTAssertFalse(AnalysisViewModel.shouldRegenerate(storedGeneratorVersions: [6, 6, 6, 6, 6]))

        let track = TrackEntity(
            title: "버전 테스트",
            sourceFilename: "version.wav",
            importedAt: Date(timeIntervalSince1970: 0),
            relativeAudioPath: "AudioFiles/version.wav"
        )
        var staleBeatmap = BeatmapGenerator.generate(
            from: AnalysisResult(
                duration: 10,
                tempo: 120,
                onsets: [],
                meanBass: 0.1,
                meanMid: 0.1,
                meanTreble: 0.1,
                meanRMS: 0.1
            ),
            difficulty: .normal,
            seed: 42
        )
        staleBeatmap.generatorVersion = 4
        let data = try JSONEncoder().encode(staleBeatmap)
        let entity = BeatmapEntity(
            difficulty: Difficulty.normal.rawValue,
            beatmapData: data,
            track: track
        )

        XCTAssertTrue(AnalysisViewModel.needsRegeneration(for: [entity]))
    }

    func testStartPersistsFiveStableBeatmapsAndReplacesExistingMaps() async throws {
        let relativePath = "AudioFiles/analysis-\(UUID().uuidString).wav"
        let audioURL = try makeAudioFixture(relativePath: relativePath)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let context = try makeInMemoryContext()
        let track = TrackEntity(
            title: "분석 테스트",
            sourceFilename: "fixture.wav",
            importedAt: Date(timeIntervalSince1970: 0),
            relativeAudioPath: relativePath,
            duration: 1
        )
        context.insert(track)
        try context.save()

        let viewModel = AnalysisViewModel()
        await viewModel.start(track: track, context: context)

        guard case .done = viewModel.state else {
            XCTFail("Expected analysis to finish, got \(viewModel.state)")
            return
        }

        let firstRun = try fetchBeatmaps(from: context)
        XCTAssertEqual(firstRun.count, Difficulty.allCases.count)
        XCTAssertEqual(
            firstRun.map(\.difficulty),
            Difficulty.allCases.map(\.rawValue)
        )
        for entity in firstRun {
            let beatmap = try JSONDecoder().decode(Beatmap.self, from: entity.beatmapData)
            XCTAssertEqual(beatmap.difficulty.rawValue, entity.difficulty)
        }

        let firstData = firstRun.map(\.beatmapData)
        await viewModel.start(track: track, context: context)

        guard case .done = viewModel.state else {
            XCTFail("Expected repeated analysis to finish, got \(viewModel.state)")
            return
        }

        let secondRun = try fetchBeatmaps(from: context)
        XCTAssertEqual(secondRun.count, Difficulty.allCases.count)
        XCTAssertEqual(secondRun.map(\.beatmapData), firstData)
    }

    private func fetchBeatmaps(from context: ModelContext) throws -> [BeatmapEntity] {
        try context.fetch(FetchDescriptor<BeatmapEntity>()).sorted {
            let left = Difficulty(rawValue: $0.difficulty)!
            let right = Difficulty(rawValue: $1.difficulty)!
            return left.ordinal < right.ordinal
        }
    }

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([TrackEntity.self, BeatmapEntity.self, ScoreRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    private func makeAudioFixture(relativePath: String) throws -> URL {
        let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let url = applicationSupportURL.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frameCount = AVAudioFrameCount(format.sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / format.sampleRate
            let click = time.truncatingRemainder(dividingBy: 0.25) < 0.004
            buffer.floatChannelData![0][frame] = click
                ? Float(0.8 * (1 - time.truncatingRemainder(dividingBy: 0.25) / 0.004))
                : 0
        }
        try file.write(from: buffer)
        return url
    }
}

private extension Difficulty {
    var ordinal: Int {
        switch self {
        case .heaven: 0
        case .easy: 1
        case .normal: 2
        case .hard: 3
        case .hell: 4
        }
    }
}
