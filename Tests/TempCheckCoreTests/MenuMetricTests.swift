import XCTest
@testable import TempCheckCore

final class MenuMetricTests: XCTestCase {
    private var sample: Snapshot { Snapshot(temperatures: [
        TemperatureSensor(id: "cpu", name: "CPU", group: .cpu, celsius: 60),
        TemperatureSensor(id: "gpu", name: "GPU", group: .gpu, celsius: 75),
        TemperatureSensor(id: "bat", name: "Bateria", group: .battery, celsius: 32)
    ], fans: [Fan(id: 1, rpm: 0)]) }
    func testChoosesRequestedGroupInsteadOfGlobalMaximum() {
        XCTAssertEqual(MenuMetric.cpu.reading(snapshot: sample, unit: .celsius, fanID: 0).text, "60 °C")
        XCTAssertEqual(MenuMetric.gpu.reading(snapshot: sample, unit: .fahrenheit, fanID: 0).text, "167 °F")
        XCTAssertEqual(MenuMetric.battery.reading(snapshot: sample, unit: .celsius, fanID: 0).text, "32 °C")
        XCTAssertEqual(MenuMetric.hottest.reading(snapshot: sample, unit: .celsius, fanID: 0).text, "75 °C")
    }
    func testMissingFanDoesNotFallbackAndStoppedFanIsZero() {
        XCTAssertEqual(MenuMetric.fan.reading(snapshot: sample, unit: .celsius, fanID: 0).text, "— RPM")
        XCTAssertEqual(MenuMetric.fan.reading(snapshot: sample, unit: .celsius, fanID: 1).text, "0 RPM")
        XCTAssertEqual(MenuMetric.cpu.reading(snapshot: Snapshot(), unit: .celsius, fanID: 0).text, "—")
    }
}
