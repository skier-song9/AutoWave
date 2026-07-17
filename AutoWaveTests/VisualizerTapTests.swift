import XCTest
@testable import AutoWave

final class VisualizerTapTests: XCTestCase {
    func testBandBinRangesAreLogSpacedAndWithinFFTNyquist() {
        let ranges = VisualizerTap.bandBinRanges(sampleRate: 44_100, fftSize: 1_024)

        XCTAssertEqual(ranges.count, 16)
        XCTAssertTrue(ranges.allSatisfy { !$0.isEmpty })
        XCTAssertEqual(ranges.first?.lowerBound, 1)
        XCTAssertLessThanOrEqual(ranges.last?.upperBound ?? .max, 512)
        XCTAssertTrue(zip(ranges, ranges.dropFirst()).allSatisfy {
            $0.0.lowerBound <= $0.1.lowerBound
                && $0.0.upperBound <= $0.1.upperBound
        })
    }
}
