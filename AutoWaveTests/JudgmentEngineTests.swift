import Foundation
import XCTest
@testable import AutoWave

final class JudgmentEngineTests: XCTestCase {
    func testWindowEdgesAreInclusiveAndClassifiedByNarrowestWindow() {
        XCTAssertEqual(
            JudgmentEngine(notes: [note(at: 1.0)]).tap(lane: 0, at: 0.955)?.judgment,
            .perfect
        )
        XCTAssertEqual(
            JudgmentEngine(notes: [note(at: 1.0)]).tap(lane: 0, at: 1.045)?.judgment,
            .perfect
        )
        XCTAssertEqual(
            JudgmentEngine(notes: [note(at: 1.0)]).tap(lane: 0, at: 0.920)?.judgment,
            .great
        )
        XCTAssertEqual(
            JudgmentEngine(notes: [note(at: 1.0)]).tap(lane: 0, at: 1.080)?.judgment,
            .great
        )
        XCTAssertEqual(
            JudgmentEngine(notes: [note(at: 1.0)]).tap(lane: 0, at: 0.885)?.judgment,
            .good
        )
        XCTAssertEqual(
            JudgmentEngine(notes: [note(at: 1.0)]).tap(lane: 0, at: 1.115)?.judgment,
            .good
        )
        XCTAssertEqual(
            JudgmentEngine(notes: [note(at: 1.0)]).tap(lane: 0, at: 0.850)?.judgment,
            .bad
        )
        XCTAssertEqual(
            JudgmentEngine(notes: [note(at: 1.0)]).tap(lane: 0, at: 1.150)?.judgment,
            .bad
        )
        let badEngine = JudgmentEngine(notes: [note(at: 1.0)])
        XCTAssertEqual(
            badEngine.tap(lane: 0, at: 1.150),
            JudgmentResult(judgment: .bad, pointsAwarded: 1, combo: 0, score: 1)
        )
        XCTAssertEqual(badEngine.judgmentCounts.bad, 1)
        XCTAssertNil(JudgmentEngine(notes: [note(at: 1.0)]).tap(lane: 0, at: 0.849))
        XCTAssertNil(JudgmentEngine(notes: [note(at: 1.0)]).tap(lane: 0, at: 1.151))
    }

    func testAdvanceEmitsMissAfterBadWindowAndResetsCombo() {
        let notes = [note(at: 1.0), note(at: 2.0)]
        let engine = JudgmentEngine(notes: notes)

        XCTAssertEqual(engine.tap(lane: 0, at: 1.0)?.combo, 1)
        XCTAssertEqual(engine.advance(to: 1.151), [])
        XCTAssertEqual(
            engine.advance(to: 2.151),
            [JudgmentResult(judgment: .miss, pointsAwarded: 0, combo: 0, score: 6)]
        )
        XCTAssertEqual(engine.judgmentCounts.miss, 1)
        XCTAssertEqual(engine.combo, 0)
        XCTAssertEqual(engine.life, 95)
    }

    func testThreePerfectsAward21PointsWithComboBonus() {
        let engine = JudgmentEngine(notes: [note(at: 1.0), note(at: 2.0), note(at: 3.0)])

        let results = [
            engine.tap(lane: 0, at: 1.0),
            engine.tap(lane: 0, at: 2.0),
            engine.tap(lane: 0, at: 3.0)
        ].compactMap { $0 }

        XCTAssertEqual(results.map(\.pointsAwarded), [6, 7, 8])
        XCTAssertEqual(results.map(\.combo), [1, 2, 3])
        XCTAssertEqual(results.map(\.score), [6, 13, 21])
        XCTAssertEqual(engine.score, 21)
        XCTAssertEqual(engine.maxCombo, 3)
    }

    func testGreatAfterTwoPerfectsUsesNewComboAsBonus() {
        let engine = JudgmentEngine(notes: [note(at: 1.0), note(at: 2.0), note(at: 3.0)])

        _ = engine.tap(lane: 0, at: 1.0)
        _ = engine.tap(lane: 0, at: 2.0)

        XCTAssertEqual(
            engine.tap(lane: 0, at: 3.080),
            JudgmentResult(judgment: .great, pointsAwarded: 6, combo: 3, score: 19)
        )
    }

    func testGoodBreaksComboAndAwardsOnlyBasePoints() {
        let engine = JudgmentEngine(
            notes: [note(at: 1.0), note(at: 2.0), note(at: 3.0), note(at: 4.0)]
        )

        XCTAssertEqual(engine.tap(lane: 0, at: 1.0)?.pointsAwarded, 6)
        XCTAssertEqual(engine.tap(lane: 0, at: 2.0)?.pointsAwarded, 7)
        XCTAssertEqual(
            engine.tap(lane: 0, at: 3.115),
            JudgmentResult(judgment: .good, pointsAwarded: 2, combo: 0, score: 15)
        )
        XCTAssertEqual(
            engine.tap(lane: 0, at: 4.080),
            JudgmentResult(judgment: .great, pointsAwarded: 4, combo: 1, score: 19)
        )
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
        XCTAssertEqual(engine.life, 95)
    }

    func testDragHeadHitAndFullHoldScoreTicksUntilFinished() {
        let drag = drag(at: 1.0, duration: 0.5, lane: 1.0)
        let engine = JudgmentEngine(notes: [drag])

        XCTAssertEqual(
            engine.beginDrag(noteID: drag.id, touchLane: 1.0, at: 1.0),
            JudgmentResult(judgment: .perfect, pointsAwarded: 6, combo: 1, score: 6)
        )

        XCTAssertEqual(
            [1.1, 1.2, 1.3, 1.4].map {
                engine.dragTick(noteID: drag.id, touchLane: 1.0, at: $0)
            },
            [
                .scored(points: 3, combo: 2),
                .scored(points: 4, combo: 3),
                .scored(points: 5, combo: 4),
                .scored(points: 6, combo: 5)
            ]
        )
        XCTAssertEqual(
            engine.dragTick(noteID: drag.id, touchLane: 1.0, at: 1.5),
            .finished
        )
        XCTAssertEqual(engine.combo, 5)
        XCTAssertEqual(engine.score, 24)
    }

    func testHeldDragFinishesAtEndWithoutRetapOrMiss() {
        let drag = drag(at: 1.0, duration: 0.5, lane: 1.0)
        let engine = JudgmentEngine(notes: [drag])
        _ = engine.beginDrag(noteID: drag.id, touchLane: 1.0, at: 1.0)

        for time in [1.1, 1.2, 1.3, 1.4] {
            XCTAssertTrue(
                ifCaseScored(engine.dragTick(noteID: drag.id, touchLane: 1.0, at: time))
            )
        }

        XCTAssertEqual(
            engine.dragTick(noteID: drag.id, touchLane: nil, at: 1.5),
            .finished
        )
        XCTAssertEqual(engine.advance(to: 1.65), [])
        XCTAssertEqual(engine.judgmentCounts.miss, 0)
    }

    func testDragTickToleranceIncludesExactlyEightTenthsAndBreaksPastIt() {
        let drag = drag(at: 1.0, duration: 1.0, lane: 1.0)
        let engine = JudgmentEngine(notes: [drag])
        _ = engine.beginDrag(noteID: drag.id, touchLane: 1.0, at: 1.0)

        XCTAssertEqual(
            engine.dragTick(noteID: drag.id, touchLane: 1.8, at: 1.1),
            .scored(points: 3, combo: 2)
        )
        XCTAssertEqual(
            engine.dragTick(noteID: drag.id, touchLane: 1.81, at: 1.2),
            .broken
        )
    }

    func testBrokenDragRemainsInactiveWhenFingerReturnsToSpine() {
        let drag = drag(at: 1.0, duration: 1.0, lane: 1.0)
        let engine = JudgmentEngine(notes: [drag])
        _ = engine.beginDrag(noteID: drag.id, touchLane: 1.0, at: 1.0)

        XCTAssertEqual(
            engine.dragTick(noteID: drag.id, touchLane: 1.81, at: 1.1),
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
        XCTAssertEqual(engine.score, 9)
        XCTAssertEqual(engine.combo, 0)
        XCTAssertEqual(engine.life, 95)
    }

    func testMovingDragUsesSteppedSpineWithTransitionTolerance() {
        let drag = drag(
            at: 1.0,
            duration: 1.0,
            lane: 1.0,
            lanePath: [LaneKeyframe(offset: 0.8, lane: 3.0)]
        )
        let engine = JudgmentEngine(notes: [drag])
        _ = engine.beginDrag(noteID: drag.id, touchLane: 1.0, at: 1.0)

        XCTAssertEqual(
            engine.dragTick(noteID: drag.id, touchLane: 2.0, at: 1.5),
            .broken
        )

        let transitionEngine = JudgmentEngine(notes: [drag])
        _ = transitionEngine.beginDrag(noteID: drag.id, touchLane: 1.0, at: 1.0)
        XCTAssertEqual(
            transitionEngine.dragTick(noteID: drag.id, touchLane: 2.0, at: 1.7),
            .scored(points: 3, combo: 2)
        )
        XCTAssertEqual(
            transitionEngine.dragTick(noteID: drag.id, touchLane: 2.0, at: 1.8),
            .scored(points: 4, combo: 3)
        )
        XCTAssertEqual(
            transitionEngine.dragTick(noteID: drag.id, touchLane: 2.0, at: 1.96),
            .broken
        )
    }

    func testMovingDragUsesBaseToleranceOutsideTransitionWindow() {
        let drag = drag(
            at: 1.0,
            duration: 1.0,
            lane: 1.0,
            lanePath: [LaneKeyframe(offset: 0.8, lane: 3.0)]
        )
        let engine = JudgmentEngine(notes: [drag])
        _ = engine.beginDrag(noteID: drag.id, touchLane: 1.0, at: 1.0)

        XCTAssertEqual(
            engine.dragTick(noteID: drag.id, touchLane: 1.8, at: 1.5),
            .scored(points: 3, combo: 2)
        )
    }

    func testBrokenDragAddsExactlyOneMissToJudgmentCounts() {
        let drag = drag(at: 1.0, duration: 1.0, lane: 1.0)
        let engine = JudgmentEngine(notes: [drag])
        _ = engine.beginDrag(noteID: drag.id, touchLane: 1.0, at: 1.0)

        XCTAssertEqual(
            engine.dragTick(noteID: drag.id, touchLane: 1.81, at: 1.1),
            .broken
        )
        XCTAssertEqual(engine.advance(to: 2.0), [])
        XCTAssertEqual(engine.judgmentCounts.miss, 1)
        XCTAssertEqual(engine.life, 95)
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

    func testMissesReduceLifeByFiveAndNeverBelowZero() {
        let engine = JudgmentEngine(notes: (1...20).map { note(at: TimeInterval($0)) })

        XCTAssertFalse(engine.isGameOver)
        XCTAssertEqual(engine.advance(to: 19.151).count, 19)
        XCTAssertEqual(engine.life, 5)
        XCTAssertFalse(engine.isGameOver)

        XCTAssertEqual(engine.advance(to: 20.151).count, 1)
        XCTAssertEqual(engine.life, 0)
        XCTAssertTrue(engine.isGameOver)

        XCTAssertEqual(engine.advance(to: 21.0), [])
        XCTAssertEqual(engine.life, 0)
        XCTAssertTrue(engine.isGameOver)
    }

    func testLifeRegeneratesAtEach200PointThresholdAndCapsAt100() {
        let engine = JudgmentEngine(
            notes: [note(at: 1.0)] + (2...41).map { note(at: TimeInterval($0)) }
        )

        _ = engine.advance(to: 1.151)
        XCTAssertEqual(engine.life, 95)

        for time in 2...18 {
            _ = engine.tap(lane: 0, at: TimeInterval(time))
        }
        XCTAssertEqual(engine.score, 238)
        XCTAssertEqual(engine.life, 96)

        for time in 19...41 {
            _ = engine.tap(lane: 0, at: TimeInterval(time))
        }
        XCTAssertEqual(engine.score, 1020)
        XCTAssertEqual(engine.life, 100)
    }

    func testMultipleScoreThresholdsInOneLargeRunAwardOneLifePerThresholdAndRespectCap() {
        let engine = JudgmentEngine(notes: (1...210).map { note(at: TimeInterval($0)) })

        for time in 1...210 {
            _ = engine.tap(lane: 0, at: TimeInterval(time))
        }

        XCTAssertEqual(engine.score, 23205)
        XCTAssertEqual(engine.life, 100)
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

    private func ifCaseScored(_ result: DragTickResult) -> Bool {
        if case .scored = result {
            return true
        }
        return false
    }
}
