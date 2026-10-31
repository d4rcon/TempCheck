import XCTest
@testable import TempCheckCore

final class ThermalAlertTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 10000)
    private func date(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }

    func testRequiresSustainedHeatAndLatchesUntilCooling() {
        var policy = ThermalAlertPolicy()
        for second in stride(from: 0, through: 50, by: 10) {
            XCTAssertFalse(policy.evaluate(temp: 95, at: date(Double(second))))
        }
        XCTAssertTrue(policy.evaluate(temp: 95, at: date(60)))
        for second in stride(from: 70, through: 1000, by: 10) {
            XCTAssertFalse(policy.evaluate(temp: 95, at: date(Double(second))))
        }
        XCTAssertFalse(policy.evaluate(temp: 84, at: date(1010)))
        for second in stride(from: 1020, through: 1070, by: 10) {
            XCTAssertFalse(policy.evaluate(temp: 95, at: date(Double(second))))
        }
        XCTAssertTrue(policy.evaluate(temp: 95, at: date(1080)))
    }

    func testMissingDataAndLongGapDoNotCountTowardsDuration() {
        var policy = ThermalAlertPolicy(sustainedDuration: 20)
        XCTAssertFalse(policy.evaluate(temp: 95, at: date(0)))
        XCTAssertFalse(policy.evaluate(temp: 95, at: date(10)))
        XCTAssertFalse(policy.evaluate(temp: nil, at: date(15)))
        XCTAssertFalse(policy.evaluate(temp: 95, at: date(20)))
        XCTAssertFalse(policy.evaluate(temp: 95, at: date(30)))
        XCTAssertTrue(policy.evaluate(temp: 95, at: date(40)))

        var gap = ThermalAlertPolicy(sustainedDuration: 20)
        XCTAssertFalse(gap.evaluate(temp: 95, at: date(0)))
        XCTAssertFalse(gap.evaluate(temp: 95, at: date(100)))
        XCTAssertFalse(gap.evaluate(temp: 95, at: date(110)))
        XCTAssertTrue(gap.evaluate(temp: 95, at: date(120)))
    }

    func testCooldownAppliesAfterRearmingAndResettingContinuity() {
        var policy = ThermalAlertPolicy(sustainedDuration: 10, cooldown: 60)
        XCTAssertFalse(policy.evaluate(temp: 95, at: date(0)))
        XCTAssertTrue(policy.evaluate(temp: 95, at: date(10)))
        XCTAssertFalse(policy.evaluate(temp: 84, at: date(20)))
        policy.resetContinuity()
        XCTAssertFalse(policy.evaluate(temp: 95, at: date(30)))
        XCTAssertFalse(policy.evaluate(temp: 95, at: date(40)))
        XCTAssertFalse(policy.evaluate(temp: 95, at: date(50)))
        XCTAssertFalse(policy.evaluate(temp: 95, at: date(60)))
        XCTAssertTrue(policy.evaluate(temp: 95, at: date(70)))
    }

    func testSnoozeAndDisabledReadingsNeverDeliver() {
        var policy = ThermalAlertPolicy(sustainedDuration: 10)
        XCTAssertFalse(policy.evaluate(temp: 95, at: date(0)))
        XCTAssertFalse(policy.evaluate(temp: 95, at: date(10), enabled: false))
        XCTAssertFalse(policy.evaluate(temp: 95, at: date(20)))
        policy.snooze(until: date(60))
        XCTAssertFalse(policy.evaluate(temp: 95, at: date(30)))
        XCTAssertFalse(policy.evaluate(temp: 95, at: date(59)))
        XCTAssertFalse(policy.evaluate(temp: 95, at: date(60)))
        XCTAssertNil(policy.snoozedUntil)
        XCTAssertTrue(policy.evaluate(temp: 95, at: date(70)))
    }

    func testSmallDipsResetDurationButDoNotRearmAnAlertedEpisode() {
        var policy = ThermalAlertPolicy(sustainedDuration: 10, cooldown: 0)
        XCTAssertFalse(policy.evaluate(temp: 95, at: date(0)))
        XCTAssertFalse(policy.evaluate(temp: 89, at: date(10)))
        XCTAssertFalse(policy.evaluate(temp: 95, at: date(20)))
        XCTAssertTrue(policy.evaluate(temp: 95, at: date(30)))
        XCTAssertFalse(policy.evaluate(temp: 89, at: date(40)))
        XCTAssertFalse(policy.evaluate(temp: 95, at: date(50)))
        XCTAssertFalse(policy.evaluate(temp: 95, at: date(60)))
        XCTAssertFalse(policy.evaluate(temp: 85, at: date(70)))
        XCTAssertFalse(policy.evaluate(temp: 95, at: date(80)))
        XCTAssertTrue(policy.evaluate(temp: 95, at: date(90)))
    }

    func testInvalidSamplesAndClockReversalBreakContinuity() {
        var policy = ThermalAlertPolicy(sustainedDuration: 10)
        for value in [Double.nan, .infinity, -1, 0, 151] {
            XCTAssertFalse(policy.evaluate(temp: 95, at: date(0)))
            XCTAssertFalse(policy.evaluate(temp: value, at: date(10)))
            XCTAssertFalse(policy.evaluate(temp: 95, at: date(20)))
            policy.resetContinuity()
        }
        XCTAssertFalse(policy.evaluate(temp: 95, at: date(30)))
        XCTAssertFalse(policy.evaluate(temp: 95, at: date(20)))
        XCTAssertTrue(policy.evaluate(temp: 95, at: date(30)))
    }
}
