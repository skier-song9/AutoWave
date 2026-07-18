import AVFoundation
import Foundation
import XCTest
@testable import AutoWave

final class BeatmapKitAnalysisTests: XCTestCase {
    func testClickTrackProducesOnsetsAt120BPM() async throws {
        let duration = 20.0
        let fixtureURL = try makeWAVFixture(duration: duration) { time in
            let offset = time.truncatingRemainder(dividingBy: 0.5)
            guard offset < 0.005 else { return 0 }
            return 0.9 * Float(1 - offset / 0.005)
        }
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let result = try await BeatmapKit.analyze(fileAt: fixtureURL, progress: nil)
        let expectedTimes = Array(stride(from: 0.5, through: 19.5, by: 0.5))

        for expectedTime in expectedTimes {
            XCTAssertTrue(
                result.onsets.contains { abs($0.time - expectedTime) <= 0.03 },
                "Missing onset near \(expectedTime)s"
            )
        }
        XCTAssertLessThanOrEqual(abs(result.onsets.count - expectedTimes.count), 2)
        XCTAssertEqual(result.tempo, 120, accuracy: 3)
    }

    func testLongClickTrackPreservesOnsetsAndBeatmapNotesNearFileEnd() async throws {
        let fixtureURL = try makeWAVFixture(duration: 120) { time in
            let offset = time.truncatingRemainder(dividingBy: 0.5)
            guard offset < 0.005 else { return 0 }
            return 0.9 * Float(1 - offset / 0.005)
        }
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let result = try await BeatmapKit.analyze(fileAt: fixtureURL, progress: nil)
        let hell = BeatmapGenerator.generate(from: result, difficulty: .hell, seed: 42)

        XCTAssertEqual(result.duration, 120, accuracy: 0.2)
        XCTAssertTrue(result.onsets.contains { $0.time >= 110 })
        XCTAssertTrue(hell.notes.contains { $0.time > 100 })
    }

    func testSustainedSineProducesAtMostTwoOnsets() async throws {
        let fixtureURL = try makeWAVFixture(duration: 10) { time in
            0.35 * Float(sin(2 * Double.pi * 440 * time))
        }
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let result = try await BeatmapKit.analyze(fileAt: fixtureURL, progress: nil)

        XCTAssertLessThanOrEqual(result.onsets.count, 2)
    }

    func testEmptyWAVThrowsDuringAnalysis() async throws {
        let fixtureURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("autowave-empty-analysis-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 22_050,
            channels: 1,
            interleaved: false
        )!
        do {
            let file = try AVAudioFile(forWriting: fixtureURL, settings: format.settings)
            XCTAssertEqual(file.length, 0)
        }

        do {
            _ = try await BeatmapKit.analyze(fileAt: fixtureURL, progress: nil)
            XCTFail("Expected empty audio analysis to throw")
        } catch {
            guard case AudioDecoderError.unusableInput = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
        }
    }

    func testBandBurstsPreserveLowAndHighSpectralDominance() async throws {
        let fixtureURL = try makeWAVFixture(duration: 8) { time in
            let section = Int(time / 0.5)
            let offset = time - Double(section) * 0.5
            guard offset < 0.2 else { return 0 }

            let frequency = section.isMultiple(of: 2) ? 100.0 : 4_000.0
            let amplitude = section.isMultiple(of: 2) ? 0.9 : 0.65
            return Float(amplitude * sin(2 * Double.pi * frequency * time))
        }
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let result = try await BeatmapKit.analyze(fileAt: fixtureURL, progress: nil)
        let lowOnsets = result.onsets.filter { isBurstStart($0.time, sectionParity: 0) }
        let highOnsets = result.onsets.filter { isBurstStart($0.time, sectionParity: 1) }

        XCTAssertGreaterThanOrEqual(lowOnsets.count, 4)
        XCTAssertGreaterThanOrEqual(highOnsets.count, 4)
        XCTAssertTrue(lowOnsets.allSatisfy { $0.bass > $0.treble })
        XCTAssertTrue(highOnsets.allSatisfy { $0.treble > $0.bass })
        XCTAssertGreaterThan(result.meanBass, result.meanTreble)
    }

    private func isBurstStart(_ time: TimeInterval, sectionParity: Int) -> Bool {
        let section = Int(time / 0.5)
        let offset = time - Double(section) * 0.5
        return section.isMultiple(of: 2) == (sectionParity == 0) && offset < 0.25
    }

    private func makeWAVFixture(
        duration: TimeInterval,
        sampleRate: Double = 22_050,
        sample: (TimeInterval) -> Float
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("autowave-analysis-\(UUID().uuidString)")
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
