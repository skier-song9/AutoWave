import AVFoundation
import SpriteKit
import XCTest
@testable import AutoWave

@MainActor
final class GameplayStabilityTests: XCTestCase {
    private var retainedViews: [SKView] = []

    func testLifeGaugeStartsAtFullHeight() {
        let scene = makeScene(
            beatmap: makeBeatmap(notes: []),
            playbackTime: { 0 },
            audioDuration: 10
        )
        let renderQueue = DispatchQueue(label: "GameplayStabilityTests.initialGauge")
        renderQueue.sync { scene.update(0) }

        // Ring-gauge HUD: full life renders as the "100%" health value label.
        let label = healthValueLabel(in: scene)
        XCTAssertFalse(label.isHidden)
        XCTAssertEqual(label.text, "100%")
    }

    func testLifeZeroHidesGaugeWithoutBuildingInvalidPath() {
        let notes = (0..<21).map { index in
            Note(
                id: UUID(),
                kind: .tap,
                time: Double(index) * 0.01,
                lane: 0,
                duration: 0,
                lanePath: []
            )
        }
        let scene = makeScene(
            beatmap: makeBeatmap(notes: notes),
            playbackTime: { 1 },
            audioDuration: 10
        )
        let renderQueue = DispatchQueue(label: "GameplayStabilityTests.lifeZero")
        renderQueue.sync { scene.update(1) }

        // Ring-gauge HUD: zero life renders as "0%" without any invalid-path crash.
        let label = healthValueLabel(in: scene)
        XCTAssertEqual(label.text, "0%")
    }

    func testUnderlyingViewEnablesMultitouch() {
        let scene = makeScene(
            beatmap: makeBeatmap(notes: []),
            playbackTime: { 0 },
            audioDuration: 10
        )

        XCTAssertTrue(scene.view?.isMultipleTouchEnabled == true)
    }

    func testAllowedNoteSpeedValuesMatchReadyModalOptions() {
        XCTAssertEqual(
            NoteSpeedMultiplierState.allowedValues,
            [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
        )
    }

    func testSetMutatesSharedNoteSpeedSourceOfTruth() {
        let speedState = NoteSpeedMultiplierState(1.0)

        speedState.set(2.0)
        XCTAssertEqual(speedState.value, 2.0, accuracy: 0.001)
    }

    func testScenePollsChangedMultiplierWithoutRecreatingScene() {
        let speedState = NoteSpeedMultiplierState(1.0)
        let scene = makeScene(
            beatmap: makeBeatmap(notes: []),
            noteSpeedState: speedState,
            playbackTime: { 0 },
            audioDuration: 10
        )
        let renderQueue = DispatchQueue(label: "GameplayStabilityTests.speed")

        XCTAssertEqual(scene.effectiveScrollSpeed, 360, accuracy: 0.001)
        speedState.set(1.5)
        renderQueue.sync { scene.update(0.1) }

        XCTAssertEqual(scene.effectiveScrollSpeed, 540, accuracy: 0.001)
    }

    func testManualStopCompletionCannotFinishClockAcrossResume() {
        let clock = PlaybackClock(playerNode: AVAudioPlayerNode())
        let initialGeneration = clock.beginPlayback()

        clock.beginManualStop()
        clock.completePlayback(for: initialGeneration)
        XCTAssertFalse(clock.isFinished)

        let resumedGeneration = clock.beginPlayback()
        clock.completePlayback(for: initialGeneration)
        XCTAssertFalse(clock.isFinished)

        clock.completePlayback(for: resumedGeneration)
        XCTAssertTrue(clock.isFinished)
    }

    func testPausedSceneIgnoresFinishedPlayback() {
        var completed = false
        let scene = makeScene(
            beatmap: makeBeatmap(notes: []),
            playbackTime: { 12 },
            playbackFinished: { true },
            audioDuration: 10,
            onComplete: { _ in completed = true }
        )
        let renderQueue = DispatchQueue(label: "GameplayStabilityTests.pausedCompletion")
        scene.isPaused = true
        renderQueue.sync { scene.update(12) }

        XCTAssertFalse(completed)
    }

    func testCompletionUsesAudioDurationFallbackWhenPlaybackCallbackStalls() {
        var completed = false
        let scene = makeScene(
            beatmap: makeBeatmap(notes: [
                Note(
                    id: UUID(),
                    kind: .tap,
                    time: 3,
                    lane: 0,
                    duration: 0,
                    lanePath: []
                )
            ]),
            playbackTime: { 12 },
            playbackFinished: { false },
            audioDuration: 10,
            onComplete: { _ in completed = true }
        )
        let renderQueue = DispatchQueue(label: "GameplayStabilityTests.audioFallback")
        renderQueue.sync { scene.update(12) }

        XCTAssertTrue(completed)
    }

    func testJudgmentLabelFadesFromUpdateLoop() {
        let scene = makeScene(
            beatmap: makeBeatmap(notes: [
                Note(
                    id: UUID(),
                    kind: .tap,
                    time: 0,
                    lane: 0,
                    duration: 0,
                    lanePath: []
                )
            ]),
            playbackTime: { 1 },
            audioDuration: 10
        )
        let renderQueue = DispatchQueue(label: "GameplayStabilityTests.judgmentFade")
        renderQueue.sync { scene.update(1) }
        let label = judgmentLabel(in: scene)
        XCTAssertEqual(label.alpha, 1, accuracy: 0.001)

        renderQueue.sync { scene.update(1.7) }

        XCTAssertLessThan(label.alpha, 1)
        XCTAssertGreaterThan(label.alpha, 0)
    }

    private func makeScene(
        beatmap: Beatmap,
        noteSpeedState: NoteSpeedMultiplierState = NoteSpeedMultiplierState(1),
        playbackTime: @escaping @Sendable () -> TimeInterval,
        playbackFinished: @escaping @Sendable () -> Bool = { false },
        audioDuration: TimeInterval,
        onComplete: @escaping (Bool) -> Void = { _ in }
    ) -> GameScene {
        let scene = GameScene(
            beatmap: beatmap,
            difficulty: .normal,
            judgmentEngine: JudgmentEngine(notes: beatmap.notes),
            visualizerTap: VisualizerTap(),
            noteSpeedState: noteSpeedState,
            playbackTime: playbackTime,
            playbackFinished: playbackFinished,
            audioDuration: audioDuration,
            onComplete: onComplete,
            onHaptic: { _ in }
        )
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 852, height: 393))
        view.presentScene(scene)
        retainedViews.append(view)
        return scene
    }

    private func makeBeatmap(notes: [Note]) -> Beatmap {
        Beatmap(
            difficulty: .normal,
            tempo: 120,
            notes: notes,
            palette: ThemePalette(hue: 0.6, saturation: 0.5, brightness: 0.5),
            generatorVersion: BeatmapGenerator.version
        )
    }

    private func healthValueLabel(in scene: GameScene) -> SKLabelNode {
        scene.children.compactMap { $0 as? SKLabelNode }
            .first { $0.text?.hasSuffix("%") == true }!
    }

    private func judgmentLabel(in scene: GameScene) -> SKLabelNode {
        scene.children.compactMap { $0 as? SKLabelNode }
            .first { $0.text == "MISS" }!
    }
}
