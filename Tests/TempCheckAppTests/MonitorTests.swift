import XCTest
import TempCheckCore
@testable import TempCheck

final class MonitorTests: XCTestCase {
    func testDemoSettingsBindToHistoryAndMenuWithoutEnablingSystemServices() async {
        await MainActor.run {
            let monitor = Monitor(demo: true)
            monitor.paused = true
            monitor.unit = .celsius
            monitor.menuMetric = .cpu
            XCTAssertTrue(monitor.menuReading.description.contains("CPU"))
            XCTAssertTrue(monitor.menuReading.text.contains("°C"))
            monitor.menuMetric = .fan; monitor.menuFanID = 1
            XCTAssertTrue(monitor.menuReading.text.contains("RPM"))
            XCTAssertTrue(monitor.menuReading.description.contains("2"))
            monitor.historyRange = .week
            XCTAssertFalse(monitor.visibleHistory.isEmpty)
            XCTAssertFalse(monitor.availableTemperatureSensors.isEmpty)
            XCTAssertFalse(monitor.selectedHistoryValues.isEmpty)
            XCTAssertNotNil(monitor.snapshot.cpuUsagePercent)
            XCTAssertNotNil(monitor.snapshot.gpuUsagePercent)
            XCTAssertFalse(monitor.notifications.canSend)
            XCTAssertFalse(monitor.loginItem.supportsAutomaticRegistration)
            XCTAssertFalse(monitor.alertsEnabled)
        }
    }

    func testSaveFastPathCompletesAfterReturningSoTerminationCanReply() async {
        let done = expectation(description: "Deferred save completion")
        await MainActor.run {
            let monitor = Monitor(demo: true), probe = CompletionProbe()
            monitor.saveHistory {
                XCTAssertTrue(probe.returned)
                done.fulfill()
            }
            probe.returned = true
        }
        await fulfillment(of: [done], timeout: 2)
    }
}

@MainActor private final class CompletionProbe { var returned = false }
