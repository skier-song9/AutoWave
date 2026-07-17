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

    func testDragNotesAreIgnoredByTapJudgmentAndTimeout() {
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
        XCTAssertEqual(engine.advance(to: 2.0), [])
        XCTAssertEqual(engine.judgmentCounts.miss, 0)
        XCTAssertEqual(engine.score, 0)
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
}
