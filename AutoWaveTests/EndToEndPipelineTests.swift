import AVFoundation
import Foundation
import XCTest
@testable import AutoWave

final class EndToEndPipelineTests: XCTestCase {
    override func setUp() {
        super.setUp()
        executionTimeAllowance = 60
    }

    func testRealisticMusicalFixtureGeneratesAllDifficulties() async throws {
        let duration = 30.0
        let fixtureURL = try makeWAVFixture(duration: duration) { time in
            let melody = 0.12 * sin(
                2 * Double.pi * 220 * time
                + 0.4 * sin(2 * Double.pi * 0.08 * time)
            )

            guard !(14.0..<15.25).contains(time) else {
                return Float(melody)
            }

            let beatOffset = time.truncatingRemainder(dividingBy: 0.5)
            let kick: Double
            if beatOffset < 0.06 {
                let envelope = 1 - beatOffset / 0.06
                kick = 0.95 * envelope * sin(2 * Double.pi * 110 * time)
            } else {
                kick = 0
            }

            let hatOffset = (time - 0.25).truncatingRemainder(dividingBy: 0.5)
            let hiHat: Double
            if time >= 0.25, hatOffset < 0.02 {
                let envelope = 1 - hatOffset / 0.02
                hiHat = 0.35 * envelope * sin(2 * Double.pi * 6_000 * time)
            } else {
                hiHat = 0
            }

            return Float(melody + kick + hiHat)
        }
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let analysis = try await BeatmapKit.analyze(fileAt: fixtureURL, progress: nil)

        XCTAssertEqual(analysis.tempo, 120, accuracy: 5)
        XCTAssertGreaterThan(analysis.onsets.count, 40)

        let difficulties: [Difficulty] = [.heaven, .easy, .normal, .hard, .hell]
        let beatmaps = difficulties.map {
            BeatmapGenerator.generate(from: analysis, difficulty: $0, seed: 42)
        }

        XCTAssertTrue(beatmaps.allSatisfy { !$0.notes.isEmpty })

        let noteCounts = beatmaps.map(\.notes.count)
        // Playground-parity lane assignment does not guarantee strict monotonicity;
        // allow a small dip (<5%) between adjacent difficulties but require overall growth.
        XCTAssertTrue(
            zip(noteCounts, noteCounts.dropFirst()).allSatisfy {
                Double($1) >= Double($0) * 0.95
            },
            "Note counts: \(noteCounts)"
        )
        XCTAssertGreaterThan(noteCounts.last ?? 0, noteCounts.first ?? 0)

        for beatmap in beatmaps {
            for note in beatmap.notes {
                XCTAssertGreaterThanOrEqual(note.time, 0)
                XCTAssertLessThanOrEqual(note.time, duration)
            }
        }

        XCTAssertTrue(beatmaps[4].notes.contains { $0.kind == .drag })
    }

    private func makeWAVFixture(
        duration: TimeInterval,
        sampleRate: Double = 22_050,
        sample: (TimeInterval) -> Float
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("autowave-end-to-end-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frameCount = Int(duration * sampleRate)
        let chunkSize = 4_096
        var frameOffset = 0

        while frameOffset < frameCount {
            let count = min(chunkSize, frameCount - frameOffset)
            let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(count)
            )!
            buffer.frameLength = AVAudioFrameCount(count)
            let samples = buffer.floatChannelData![0]
            for index in 0..<count {
                let time = TimeInterval(frameOffset + index) / sampleRate
                samples[index] = sample(time)
            }
            try file.write(from: buffer)
            frameOffset += count
        }

        return url
    }
}
