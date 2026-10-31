import XCTest
@testable import TempCheckCore

final class SystemLoadTests: XCTestCase {
    private func ticks(_ user: UInt32 = 0, _ system: UInt32 = 0, _ idle: UInt32 = 0, _ nice: UInt32 = 0) -> CPUTicks {
        CPUTicks(user: user, system: system, idle: idle, nice: nice)
    }

    func testCPULoadUsesIntervalAndAllActiveStates() {
        var reader = CPULoadAccumulator(processorCount: 4, ticksPerSecond: 100)
        XCTAssertNil(reader.consume(ticks(100, 100, 100, 100), at: 0))
        XCTAssertEqual(reader.consume(ticks(120, 110, 150, 120), at: 1), 50)
        XCTAssertEqual(reader.consume(ticks(120, 110, 250, 120), at: 2), 0)
        XCTAssertEqual(reader.consume(ticks(170, 160, 250, 120), at: 3), 100)
    }

    func testCPUCounterWrapIsHandledWithoutSpikes() {
        var reader = CPULoadAccumulator(processorCount: 4, ticksPerSecond: 100)
        XCTAssertNil(reader.consume(ticks(UInt32.max - 19, 0, 50), at: 0))
        XCTAssertEqual(reader.consume(ticks(20, 0, 90), at: 1), 50)
    }

    func testCPUCounterResetUnavailableAndLongGapsRequireNewBaseline() {
        var reader = CPULoadAccumulator(processorCount: 4, ticksPerSecond: 100)
        XCTAssertNil(reader.consume(ticks(100, 0, 100), at: 0))
        XCTAssertNil(reader.consume(ticks(10, 0, 10), at: 1))
        XCTAssertEqual(reader.consume(ticks(20, 0, 20), at: 2), 50)
        XCTAssertNil(reader.consume(nil, at: 3))
        XCTAssertNil(reader.consume(ticks(30, 0, 30), at: 4))
        XCTAssertNil(reader.consume(ticks(40, 0, 40), at: 200))
        XCTAssertEqual(reader.consume(ticks(50, 0, 50), at: 201), 50)
        reader.reset()
        XCTAssertNil(reader.consume(ticks(60, 0, 60), at: 202))
    }

    func testCPUInvalidIntervalsAndImpossibleCounterJumpRemainUnknown() {
        var reader = CPULoadAccumulator(processorCount: 1, ticksPerSecond: 100)
        XCTAssertNil(reader.consume(ticks(), at: 0))
        XCTAssertNil(reader.consume(ticks(10000), at: 1))
        XCTAssertNil(reader.consume(ticks(10001), at: 1))
        XCTAssertNil(reader.consume(ticks(10001), at: 2))
        XCTAssertNil(reader.consume(ticks(10002), at: .nan))
    }

    func testGPUReportsZeroAndRejectsMissingMalformedAndEngineOnlyData() {
        XCTAssertEqual(GPUUsageDecoder.percentage(["Device Utilization %": NSNumber(value: 0)]), 0)
        XCTAssertEqual(GPUUsageDecoder.percentage(["Device Utilization %": NSNumber(value: 36.5)]), 36.5)
        XCTAssertEqual(GPUUsageDecoder.percentage(["GPU Activity(%)": NSNumber(value: 100)]), 100)
        XCTAssertNil(GPUUsageDecoder.percentage([:]))
        XCTAssertNil(GPUUsageDecoder.percentage(["Device Utilization %": "25"]))
        XCTAssertNil(GPUUsageDecoder.percentage(["Device Utilization %": NSNumber(value: true)]))
        XCTAssertNil(GPUUsageDecoder.percentage(["Device Utilization %": NSNumber(value: Double.nan)]))
        XCTAssertNil(GPUUsageDecoder.percentage(["Device Utilization %": NSNumber(value: 101)]))
        XCTAssertNil(GPUUsageDecoder.percentage(["Renderer Utilization %": 40, "Tiler Utilization %": 60]))
    }

    func testDeviceGPUMetricTakesPriorityOverFallback() {
        XCTAssertEqual(GPUUsageDecoder.percentage(["Device Utilization %": 20, "GPU Activity(%)": 80]), 20)
        XCTAssertEqual(GPUUsageDecoder.percentage(["Device Utilization %": -1, "GPU Activity(%)": 80]), 80)
    }
}
