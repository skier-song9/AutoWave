import AVFoundation
import SpriteKit
import SwiftData
import XCTest
@testable import AutoWave

@MainActor
final class GameplayStartRegressionTests: XCTestCase {
    func testGameplayStartAndFirstUpdatesDoNotHang() async throws {
        // 1. Fixture audio in real Application Support (audioURL resolves there).
        let supportURL = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let audioDir = supportURL.appendingPathComponent("AudioFiles", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        let relativePath = "AudioFiles/freeze-repro-\(UUID().uuidString).wav"
        let audioURL = supportURL.appendingPathComponent(relativePath)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let seconds = 8.0
        do {
            let format = AVAudioFormat(standardFormatWithSampleRate: 22_050, channels: 1)!
            let file = try AVAudioFile(forWriting: audioURL, settings: format.settings)
            let frameCount = AVAudioFrameCount(format.sampleRate * seconds)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
            buffer.frameLength = frameCount
            for frame in 0..<Int(frameCount) {
                let t = Double(frame) / format.sampleRate
                let click: Float = t.truncatingRemainder(dividingBy: 0.5) < 0.01 ? 0.9 : 0.0
                buffer.floatChannelData![0][frame] = click + 0.05 * sin(Float(t) * 2 * .pi * 220)
            }
            try file.write(from: buffer)
        } // writer closed here so the reader sees the full file

        // 2. Real analysis + generation for the chosen difficulty.
        let analysis = try await BeatmapKit.analyze(fileAt: audioURL, progress: nil)
        let generated = BeatmapGenerator.generate(from: analysis, difficulty: .normal, seed: 42)
        XCTAssertFalse(generated.notes.isEmpty, "fixture produced empty beatmap")

        // 3. SwiftData entities.
        let schema = Schema([TrackEntity.self, BeatmapEntity.self, ScoreRecord.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let track = TrackEntity(
            title: "FreezeRepro",
            sourceFilename: "freeze.wav",
            importedAt: Date(),
            relativeAudioPath: relativePath,
            duration: seconds
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let beatmapEntity = BeatmapEntity(
            difficulty: Difficulty.normal.rawValue,
            beatmapData: try encoder.encode(generated),
            track: track
        )
        context.insert(track)
        context.insert(beatmapEntity)
        try context.save()

        // 4. The path the app takes on difficulty selection.
        let viewModel = GameplayViewModel(track: track, difficulty: .normal)
        var completed = false
        viewModel.start(context: context) { _ in completed = true }

        guard case .ready = viewModel.state else {
            return XCTFail("start() did not reach .ready: \(viewModel.state)")
        }
        let scene = try XCTUnwrap(viewModel.scene, "scene missing after start")

        // 5. Drive the scene like SpriteKit would (didMove needs a view).
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 852, height: 393))
        view.presentScene(scene)
        let renderQueue = DispatchQueue(label: "GameplayStartRegressionTests.renderQueue")
        for step in 0..<120 {
            renderQueue.sync {
                scene.update(CACurrentMediaTime() + Double(step) / 60.0)
            }
        }
        // Time jumps exercise multiple advanceDragTicks iterations on the render queue.
        for time in [3.0, 3.5] {
            renderQueue.sync {
                scene.update(CACurrentMediaTime() + time)
            }
        }

        // A fully missed run must render the life-zero state without rebuilding an invalid path.
        let lifeZeroNotes = (0..<21).map { index in
            Note(
                id: UUID(),
                kind: .tap,
                time: Double(index) * 0.01,
                lane: 0,
                duration: 0,
                lanePath: []
            )
        }
        let lifeZeroBeatmap = Beatmap(
            difficulty: .normal,
            tempo: 120,
            notes: lifeZeroNotes,
            palette: generated.palette,
            generatorVersion: generated.generatorVersion,
            themeID: generated.themeID,
            laneCount: generated.laneCount
        )
        let lifeZeroEngine = JudgmentEngine(notes: lifeZeroNotes)
        let lifeZeroScene = GameScene(
            beatmap: lifeZeroBeatmap,
            difficulty: .normal,
            judgmentEngine: lifeZeroEngine,
            visualizerTap: VisualizerTap(),
            playbackTime: { 1 },
            playbackFinished: { false },
            audioDuration: seconds,
            onComplete: { _ in },
            onHaptic: { _ in }
        )
        view.presentScene(lifeZeroScene)
        renderQueue.sync {
            lifeZeroScene.update(1)
        }
        XCTAssertTrue(lifeZeroEngine.isGameOver)

        _ = completed
        viewModel.stop()
    }
}
