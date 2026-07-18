import CoreGraphics
import XCTest
@testable import AutoWave

final class GameplayRulesTests: XCTestCase {
    func testLaneAreaUsesSeventyPercentOfSceneWidth() {
        let rect = GameplayLayout.laneAreaRect(in: CGSize(width: 1_000, height: 500))

        XCTAssertEqual(rect.width, 700, accuracy: 0.001)
        XCTAssertEqual(rect.midX, 500, accuracy: 0.001)
    }

    func testRibbonTailTrailsBehindTheHitHead() {
        let positions = GameplayLayout.ribbonPositions(
            hitLineY: 100,
            timeToHit: 0.4,
            duration: 1.0,
            scrollSpeed: 200
        )

        XCTAssertEqual(positions.head, 180, accuracy: 0.001)
        XCTAssertEqual(positions.tail, 380, accuracy: 0.001)
        XCTAssertGreaterThan(positions.tail, positions.head)
    }

    func testGameplaySanitizerRemovesTapInsideDragLaneSpan() {
        let drag = Note(
            id: UUID(),
            kind: .drag,
            time: 4,
            lane: 1,
            duration: 1,
            lanePath: [LaneKeyframe(offset: 0.5, lane: 2)]
        )
        let conflictingTap = Note(
            id: UUID(), kind: .tap, time: 4.5, lane: 2, duration: 0, lanePath: []
        )
        let safeTap = Note(
            id: UUID(), kind: .tap, time: 4.5, lane: 3, duration: 0, lanePath: []
        )

        let notes = GameplayBeatmapSanitizer.removeTapConflicts(from: [drag, conflictingTap, safeTap])

        XCTAssertEqual(notes, [drag, safeTap])
    }
}
