import CoreGraphics
import XCTest
@testable import AutoWave

final class GameplayRulesTests: XCTestCase {
    func testPerspectiveLaneWidthGrowsMonotonically() {
        let projection = PerspectiveProjection(
            centerX: 500,
            topY: 500,
            hitLineY: 100,
            bottomLaneWidth: 175,
            laneCount: 4
        )

        XCTAssertLessThan(projection.laneWidth(at: 0), projection.laneWidth(at: 0.5))
        XCTAssertLessThan(projection.laneWidth(at: 0.5), projection.laneWidth(at: 1))
    }

    func testPerspectiveLaneCentersStaySymmetricAroundCenter() {
        let projection = PerspectiveProjection(
            centerX: 500,
            topY: 500,
            hitLineY: 100,
            bottomLaneWidth: 175,
            laneCount: 4
        )

        let left = projection.laneCenterX(0, at: 0.4)
        let right = projection.laneCenterX(3, at: 0.4)

        XCTAssertEqual(left + right, projection.centerX * 2, accuracy: 0.001)
    }

    func testPerspectiveAtHitLineMatchesBottomLaneGeometry() {
        let projection = PerspectiveProjection(
            centerX: 500,
            topY: 500,
            hitLineY: 100,
            bottomLaneWidth: 175,
            laneCount: 4
        )

        XCTAssertEqual(projection.laneWidth(at: 1), 175, accuracy: 0.001)
        XCTAssertEqual(projection.laneCenterX(0, at: 1), 237.5, accuracy: 0.001)
        XCTAssertEqual(projection.scale(at: 0), 0.22, accuracy: 0.001)
        XCTAssertEqual(projection.scale(at: 1), 1, accuracy: 0.001)
        XCTAssertEqual(projection.y(at: 0), projection.topY, accuracy: 0.001)
        XCTAssertEqual(projection.y(at: 1), projection.hitLineY, accuracy: 0.001)
    }

    func testPerspectiveLaneWidthMatchesProjectedScale() {
        let projection = PerspectiveProjection(
            centerX: 500,
            topY: 500,
            hitLineY: 100,
            bottomLaneWidth: 175,
            laneCount: 4
        )

        for progress in [CGFloat(0), 0.25, 0.5, 0.75, 1] {
            XCTAssertEqual(
                projection.laneWidth(at: progress),
                projection.bottomLaneWidth * projection.scale(at: progress),
                accuracy: 0.001
            )
        }
    }

    func testPerspectiveYMappingAcceleratesTowardHitLineAcrossEqualTimeDeltas() {
        let projection = PerspectiveProjection(
            centerX: 500,
            topY: 500,
            hitLineY: 100,
            bottomLaneWidth: 175,
            laneCount: 4
        )
        let timesToHit: [TimeInterval] = [2, 1.5, 1, 0.5, 0]
        let yPositions = timesToHit.map { timeToHit in
            projection.y(at: projection.progress(timeToHit: timeToHit, scrollSpeed: 200))
        }
        let screenYDelta = zip(yPositions, yPositions.dropFirst()).map { $0.0 - $0.1 }

        XCTAssertTrue(screenYDelta[0] < screenYDelta[1])
        XCTAssertTrue(screenYDelta[1] < screenYDelta[2])
        XCTAssertTrue(screenYDelta[2] < screenYDelta[3])
    }

    func testLaneAreaUsesSeventyPercentOfSceneWidth() {
        let rect = GameplayLayout.laneAreaRect(in: CGSize(width: 1_000, height: 500))

        XCTAssertEqual(rect.width, 700, accuracy: 0.001)
        XCTAssertEqual(rect.midX, 500, accuracy: 0.001)
    }

    func testLaneCoordinateRejectsScoreAndLifeGutters() {
        let size = CGSize(width: 1_000, height: 500)
        let laneArea = GameplayLayout.laneAreaRect(in: size)
        let laneWidth = laneArea.width / 4

        XCTAssertNil(
            GameplayLayout.laneCoordinate(
                for: CGPoint(x: 40, y: 250),
                in: laneArea,
                laneWidth: laneWidth
            )
        )
        XCTAssertNil(
            GameplayLayout.laneCoordinate(
                for: CGPoint(x: 960, y: 250),
                in: laneArea,
                laneWidth: laneWidth
            )
        )
        XCTAssertNotNil(
            GameplayLayout.laneCoordinate(
                for: CGPoint(x: laneArea.minX - laneWidth * 0.25, y: 250),
                in: laneArea,
                laneWidth: laneWidth
            )
        )
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
