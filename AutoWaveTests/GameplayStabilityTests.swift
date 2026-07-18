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

        let fill = gaugeFill(in: scene)
        XCTAssertFalse(fill.isHidden)
        XCTAssertEqual(fill.xScale, 1, accuracy: 0.001)
        XCTAssertEqual(fill.yScale, 1, accuracy: 0.001)
        XCTAssertGreaterThan(fill.path?.boundingBox.height ?? 0, 0)
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

        let fill = gaugeFill(in: scene)
        XCTAssertTrue(fill.isHidden)
        XCTAssertEqual(fill.yScale, 0, accuracy: 0.001)
    }

    func testUnderlyingViewEnablesMultitouch() {
        let scene = makeScene(
            beatmap: makeBeatmap(notes: []),
            playbackTime: { 0 },
            audioDuration: 10
        )

        XCTAssertTrue(scene.view?.isMultipleTouchEnabled == true)
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

    private func gaugeFill(in scene: GameScene) -> SKShapeNode {
        scene.children.compactMap { $0 as? SKShapeNode }
            .first { $0.zPosition == 13 }!
    }

    private func judgmentLabel(in scene: GameScene) -> SKLabelNode {
        scene.children.compactMap { $0 as? SKLabelNode }
            .first { $0.text == "미스" }!
    }
}
