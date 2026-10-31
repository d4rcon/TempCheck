import XCTest
import CSensors
@testable import TempCheckCore

final class ReadingTests: XCTestCase {
    private func decode(_ type: String, _ bytes: [UInt8]) -> Double? {
        var value = TCValue()
        value.type = type.utf8.reduce(0) { $0 << 8 | UInt32($1) }; value.size = UInt32(bytes.count)
        withUnsafeMutableBytes(of: &value.bytes) { buffer in for (i, byte) in bytes.enumerated() { buffer[i] = byte } }
        var number: Double = 0
        return tc_decode(&value, &number) ? number : nil
    }
    func testSMCNumericFormats() {
        XCTAssertEqual(decode("sp78", [0x37, 0x80]), 55.5)
        XCTAssertEqual(decode("sp78", [0xff, 0x80]), -0.5)
        XCTAssertEqual(decode("fpe2", [0x1f, 0x40]), 2000)
        XCTAssertEqual(decode("flt ", [0, 0, 0x5c, 0x42]), 55)
        XCTAssertEqual(decode("ui8 ", [0]), 0)
        XCTAssertEqual(decode("ui32", [0, 0, 0x10, 0]), 4096)
    }
    func testRejectsUnsupportedOrMalformedSMCData() {
        XCTAssertNil(decode("ch8*", [1, 2]))
        XCTAssertNil(decode("sp78", [55]))
        XCTAssertNil(decode("flt ", [0, 0, 0x80, 0x7f]))
        XCTAssertNil(decode("flt ", [0, 0, 0xc0, 0x7f]))
        XCTAssertNil(decode("spzz", [1, 2]))
    }
    func testStoppedFanIsDifferentFromMissingReading() {
        XCTAssertEqual(ReadingRules.rpm(0), 0)
        XCTAssertNil(ReadingRules.rpm(nil))
        XCTAssertNil(ReadingRules.rpm(-1))
        XCTAssertNil(ReadingRules.rpm(.infinity))
        XCTAssertNil(ReadingRules.temperature(0))
        XCTAssertNil(ReadingRules.temperature(.nan))
        XCTAssertNil(ReadingRules.temperature(300))
        XCTAssertEqual(ReadingRules.fanCount(0), 0)
        XCTAssertNil(ReadingRules.fanCount(nil))
        XCTAssertNil(ReadingRules.fanCount(1.5))
    }
    func testHistoryRetentionAndMissingSamples() {
        var history = History(); let start = Date(timeIntervalSince1970: 10000)
        for i in 0...1000 {
            history.append(Snapshot(date: start.addingTimeInterval(Double(i)), temperatures: [
                TemperatureSensor(id: "test", name: "test", group: .cpu, celsius: i % 2 == 0 ? 50 : nil)
            ]))
        }
        XCTAssertEqual(history.samples.count, 901)
        XCTAssertEqual(history.samples.first?.date, start.addingTimeInterval(100))
        XCTAssertEqual(history.values(sensorID: "test").count, 451)
        XCTAssertTrue(history.values(sensorID: "test").allSatisfy { $0 == 50 })
    }
    func testCSVPreservesUnknownAndZero() {
        var history = History()
        history.append(Snapshot(date: Date(timeIntervalSince1970: 0), temperatures: [
            TemperatureSensor(id: "a,\"b", name: "sensor", group: .other, celsius: nil)
        ], fans: [Fan(id: 0, rpm: 0), Fan(id: 1, rpm: nil)]))
        let csv = history.csv()
        XCTAssertTrue(csv.contains("\"a,\"\"b\",temperature,,C"))
        XCTAssertTrue(csv.contains("fan0,fan,0.0,RPM"))
        XCTAssertTrue(csv.contains("fan1,fan,,RPM"))
    }
    func testUnitsAndHottestSensor() {
        XCTAssertEqual(TemperatureUnit.fahrenheit.convert(100), 212)
        XCTAssertEqual(TemperatureUnit.celsius.format(nil), "—")
        let sample = Snapshot(temperatures: [
            TemperatureSensor(id: "missing", name: "missing", group: .cpu, celsius: nil),
            TemperatureSensor(id: "hot", name: "hot", group: .gpu, celsius: 80),
            TemperatureSensor(id: "cool", name: "cool", group: .cpu, celsius: 30)
        ])
        XCTAssertEqual(sample.hottest?.id, "hot")
        XCTAssertNil(Snapshot().hottest)
    }
    func testSensorLabelsPreserveUncertainLocations() {
        XCTAssertEqual(SensorReader.label("TB0T").1, .battery)
        XCTAssertEqual(SensorReader.label("T???").0, "Czujnik T???")
        XCTAssertEqual(SensorReader.label("T???").1, .other)
        #if arch(arm64)
        XCTAssertEqual(SensorReader.label("Tp0V").1, .cpu)
        XCTAssertTrue(SensorReader.label("Tp0V").0.contains("Tp0V"))
        XCTAssertEqual(SensorReader.label("Tf14").1, .gpu)
        XCTAssertEqual(SensorReader.label("Tf04").1, .cpu)
        #endif
    }
}
