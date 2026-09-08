import XCTest
import CoreGraphics
@testable import BrimCore

final class NotchSizingTests: XCTestCase {
    func testSizeIsClampedToWhatStillWorksOnAScreenEdge() {
        XCTAssertEqual(NotchSize(scale: 0.1).scale, NotchSize.range.lowerBound)
        XCTAssertEqual(NotchSize(scale: 12).scale, NotchSize.range.upperBound)
        XCTAssertEqual(NotchSize(scale: .nan).scale, 1, "nonsense falls back to the designed size")
        XCTAssertEqual(NotchSize(scale: .infinity).scale, 1)
    }

    /// The slider moves in whole steps, and two sizes chosen the same way have to
    /// compare equal, or the store saves and rebuilds the notch on every drag frame.
    func testSizeSnapsToItsStepAndComparesEqual() {
        XCTAssertEqual(NotchSize(scale: 1.14), NotchSize(scale: 1.16))
        XCTAssertEqual(NotchSize(scale: 1.14).label, "115%")
        XCTAssertEqual(NotchSize(scale: 0.83), NotchSize(scale: 0.85))
        XCTAssertNotEqual(NotchSize(scale: 1.1), NotchSize(scale: 1.15))
        XCTAssertTrue(NotchSize(scale: 1).isStandard)
        XCTAssertEqual(NotchSize.standard.label, "100%")
    }

    func testSavedSizeSurvivesARelaunchAndAMissingPreferenceDoesNot() {
        XCTAssertEqual(NotchSize(saved: nil), .standard, "the first launch is the designed size")
        XCTAssertEqual(NotchSize(saved: 1.25).scale, 1.25)
        XCTAssertEqual(NotchSize(saved: 0.0), .init(scale: NotchSize.range.lowerBound),
                       "a zero from a corrupt preference must not collapse the notch to nothing")
        XCTAssertEqual(NotchSize(saved: 4), .init(scale: NotchSize.range.upperBound))
    }

    /// Layout is rounded and type is not: a column of items must not accumulate a
    /// fractional drift, while a number under a ring should grow as smoothly as it.
    func testMeasurementsRoundButTypeDoesNot() {
        let size = NotchSize(scale: 1.15)
        XCTAssertEqual(size.scaled(36), 41)
        XCTAssertEqual(size.scaled(13), 15)
        XCTAssertEqual(size.scaledType(13), 14.95, accuracy: 0.0001)
        XCTAssertEqual(NotchSize.standard.scaled(66), 66, "the designed size changes nothing")
        XCTAssertEqual(NotchSize.standard.scaledType(13), 13)
    }

    func testEveryMeasurementGrowsWithTheSize() {
        var previous: [CGFloat] = []
        for percent in stride(from: NotchSize.range.lowerBound, through: NotchSize.range.upperBound, by: 0.05) {
            let size = NotchSize(scale: percent)
            let measurements = [66, 56, 42, 36, 26, 20, 12, 5].map(size.scaled)
            XCTAssertTrue(measurements.allSatisfy { $0 > 0 }, "nothing scales away to nothing")
            if !previous.isEmpty {
                for (larger, smaller) in zip(measurements, previous) {
                    XCTAssertGreaterThanOrEqual(larger, smaller)
                }
            }
            previous = measurements
        }
    }
}
