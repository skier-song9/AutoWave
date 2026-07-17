import XCTest
@testable import AutoWave

final class GameplaySummaryTests: XCTestCase {
    func testFailedSummaryPreservesFailedRunFlag() {
        let summary = GameplaySummary(
            score: 0,
            maxCombo: 0,
            judgmentCounts: JudgmentCounts(),
            failed: true
        )

        XCTAssertTrue(summary.failed)
    }
}
