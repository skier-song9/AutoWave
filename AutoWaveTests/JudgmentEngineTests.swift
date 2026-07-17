import Foundation
import XCTest
@testable import AutoWave

final class JudgmentEngineTests: XCTestCase {
    func testWindowEdgesAreInclusiveAndClassifiedByNarrowestWindow() {
        XCTAssertEqual(
            JudgmentEngine(notes: [note(at: 1.0)]).tap(lane: 0, at: 0.95)?.judgment,
            .perfect
        )
        XCTAssertEqual(
            JudgmentEngine(notes: [note(at: 1.0)]).tap(lane: 0, at: 1.05)?.judgment,
            .perfect
        )
        XCTAssertEqual(
            JudgmentEngine(notes: [note(at: 1.0)]).tap(lane: 0, at: 0.90)?.judgment,
            .great
        )
        XCTAssertEqual(
            JudgmentEngine(notes: [note(at: 1.0)]).tap(lane: 0, at: 1.10)?.judgment,
            .great
        )
        XCTAssertEqual(
            JudgmentEngine(notes: [note(at: 1.0)]).tap(lane: 0, at: 0.85)?.judgment,
            .good
        )
        XCTAssertEqual(
            JudgmentEngine(notes: [note(at: 1.0)]).tap(lane: 0, at: 1.15)?.judgment,
            .good
        )
        XCTAssertNil(JudgmentEngine(notes: [note(at: 1.0)]).tap(lane: 0, at: 0.849))
        XCTAssertNil(JudgmentEngine(notes: [note(at: 1.0)]).tap(lane: 0, at: 1.151))
    }

    func testAdvanceEmitsMissAfterGoodWindowAndResetsCombo() {
        let notes = [note(at: 1.0), note(at: 2.0)]
        let engine = JudgmentEngine(notes: notes)

        XCTAssertEqual(engine.tap(lane: 0, at: 1.0)?.combo, 1)
        XCTAssertEqual(engine.advance(to: 1.151), [])
        XCTAssertEqual(
            engine.advance(to: 2.151),
            [JudgmentResult(judgment: .miss, pointsAwarded: 0, combo: 0, score: 100)]
        )
        XCTAssertEqual(engine.judgmentCounts.miss, 1)
        XCTAssertEqual(engine.combo, 0)
    }

    func testThreePerfectsAward303PointsWithComboMultiplier() {
        let engine = JudgmentEngine(notes: [note(at: 1.0), note(at: 2.0), note(at: 3.0)])

        let results = [
            engine.tap(lane: 0, at: 1.0),
            engine.tap(lane: 0, at: 2.0),
            engine.tap(lane: 0, at: 3.0)
        ].compactMap { $0 }

        XCTAssertEqual(results.map(\.pointsAwarded), [100, 101, 102])
        XCTAssertEqual(results.map(\.combo), [1, 2, 3])
        XCTAssertEqual(results.map(\.score), [100, 201, 303])
        XCTAssertEqual(engine.score, 303)
        XCTAssertEqual(engine.maxCombo, 3)
    }

    func testTapConsumesNearestUnconsumedNoteInLane() {
        let engine = JudgmentEngine(notes: [note(at: 1.0), note(at: 1.12)])

        XCTAssertEqual(engine.tap(lane: 0, at: 1.08)?.judgment, .perfect)
        XCTAssertEqual(engine.tap(lane: 0, at: 1.0)?.judgment, .perfect)
        XCTAssertNil(engine.tap(lane: 0, at: 1.0))
    }

    func testDragHeadTimeoutEmitsSingleMissAndTapCannotConsumeDrag() {
        let drag = Note(
            id: UUID(),
            kind: .drag,
            time: 1.0,
            lane: 0,
            duration: 1.0,
            lanePath: []
        )
        let engine = JudgmentEngine(notes: [drag])

        XCTAssertNil(engine.tap(lane: 0, at: 1.0))
        XCTAssertEqual(
            engine.advance(to: 2.0),
            [JudgmentResult(judgment: .miss, pointsAwarded: 0, combo: 0, score: 0)]
        )
        XCTAssertEqual(engine.judgmentCounts.miss, 1)
        XCTAssertEqual(engine.score, 0)
    }

    func testDragHeadHitAndFullHoldScoreTicksUntilFinished() {
        let drag = drag(at: 1.0, duration: 0.5, lane: 1.0)
        let engine = JudgmentEngine(notes: [drag])

        XCTAssertEqual(
            engine.beginDrag(noteID: drag.id, touchLane: 1.0, at: 1.0),
            JudgmentResult(judgment: .perfect, pointsAwarded: 100, combo: 1, score: 100)
        )

        XCTAssertEqual(
            [1.1, 1.2, 1.3, 1.4].map {
                engine.dragTick(noteID: drag.id, touchLane: 1.0, at: $0)
            },
            [
                .scored(points: 10, combo: 2),
                .scored(points: 10, combo: 3),
                .scored(points: 10, combo: 4),
                .scored(points: 10, combo: 5)
            ]
        )
        XCTAssertEqual(
            engine.dragTick(noteID: drag.id, touchLane: 1.0, at: 1.5),
            .finished
        )
        XCTAssertEqual(engine.combo, 5)
        XCTAssertEqual(engine.score, 140)
    }

    func testDragTickToleranceIncludesExactlySixTenthsAndBreaksPastIt() {
        let drag = drag(at: 1.0, duration: 1.0, lane: 1.0)
        let engine = JudgmentEngine(notes: [drag])
        _ = engine.beginDrag(noteID: drag.id, touchLane: 1.0, at: 1.0)

        XCTAssertEqual(
            engine.dragTick(noteID: drag.id, touchLane: 1.6, at: 1.1),
            .scored(points: 10, combo: 2)
        )
        XCTAssertEqual(
            engine.dragTick(noteID: drag.id, touchLane: 1.61, at: 1.2),
            .broken
        )
    }

    func testBrokenDragRemainsInactiveWhenFingerReturnsToSpine() {
        let drag = drag(at: 1.0, duration: 1.0, lane: 1.0)
        let engine = JudgmentEngine(notes: [drag])
        _ = engine.beginDrag(noteID: drag.id, touchLane: 1.0, at: 1.0)

        XCTAssertEqual(
            engine.dragTick(noteID: drag.id, touchLane: 1.61, at: 1.1),
            .broken
        )
        let scoreAfterBreak = engine.score

        XCTAssertEqual(
            engine.dragTick(noteID: drag.id, touchLane: 1.0, at: 1.2),
            .inactive
        )
        XCTAssertEqual(
            engine.dragTick(noteID: drag.id, touchLane: 1.0, at: 1.3),
            .inactive
        )
        XCTAssertEqual(engine.score, scoreAfterBreak)
        XCTAssertEqual(engine.combo, 0)
    }

    func testFingerLiftBreaksDragWithPermanentInactiveState() {
        let drag = drag(at: 1.0, duration: 1.0, lane: 1.0)
        let engine = JudgmentEngine(notes: [drag])
        _ = engine.beginDrag(noteID: drag.id, touchLane: 1.0, at: 1.0)
        _ = engine.dragTick(noteID: drag.id, touchLane: 1.0, at: 1.1)

        XCTAssertEqual(
            engine.dragTick(noteID: drag.id, touchLane: nil, at: 1.2),
            .broken
        )
        XCTAssertEqual(
            engine.dragTick(noteID: drag.id, touchLane: 1.0, at: 1.3),
            .inactive
        )
        XCTAssertEqual(engine.score, 110)
        XCTAssertEqual(engine.combo, 0)
    }

    func testMovingDragUsesInterpolatedSpineLane() {
        let drag = drag(
            at: 1.0,
            duration: 1.0,
            lane: 1.0,
            lanePath: [LaneKeyframe(offset: 1.0, lane: 2.5)]
        )
        let engine = JudgmentEngine(notes: [drag])
        _ = engine.beginDrag(noteID: drag.id, touchLane: 1.0, at: 1.0)

        XCTAssertEqual(
            engine.dragTick(noteID: drag.id, touchLane: 1.75, at: 1.5),
            .scored(points: 10, combo: 2)
        )
    }

    func testBrokenDragAddsExactlyOneMissToJudgmentCounts() {
        let drag = drag(at: 1.0, duration: 1.0, lane: 1.0)
        let engine = JudgmentEngine(notes: [drag])
        _ = engine.beginDrag(noteID: drag.id, touchLane: 1.0, at: 1.0)

        XCTAssertEqual(
            engine.dragTick(noteID: drag.id, touchLane: 1.61, at: 1.1),
            .broken
        )
        XCTAssertEqual(engine.advance(to: 2.0), [])
        XCTAssertEqual(engine.judgmentCounts.miss, 1)
    }

    func testMissingDragHeadEmitsOneMissAtHeadTimeout() {
        let drag = drag(at: 1.0, duration: 1.0, lane: 1.0)
        let engine = JudgmentEngine(notes: [drag])

        XCTAssertEqual(
            engine.advance(to: 1.151),
            [JudgmentResult(judgment: .miss, pointsAwarded: 0, combo: 0, score: 0)]
        )
        XCTAssertEqual(engine.advance(to: 2.0), [])
        XCTAssertEqual(
            engine.dragTick(noteID: drag.id, touchLane: 1.0, at: 1.2),
            .inactive
        )
        XCTAssertEqual(engine.judgmentCounts.miss, 1)
    }

    private func note(at time: TimeInterval) -> Note {
        Note(
            id: UUID(),
            kind: .tap,
            time: time,
            lane: 0,
            duration: 0,
            lanePath: []
        )
    }

    private func drag(
        at time: TimeInterval,
        duration: TimeInterval,
        lane: Double,
        lanePath: [LaneKeyframe] = []
    ) -> Note {
        Note(
            id: UUID(),
            kind: .drag,
            time: time,
            lane: lane,
            duration: duration,
            lanePath: lanePath
        )
    }
}
