import XCTest
@testable import TempCheckCore

final class HistoryTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_800_000_000)
    private func snapshot(_ offset: Double, temperature: Double? = 50, cpu: Double? = nil, gpu: Double? = nil) -> Snapshot {
        Snapshot(date: epoch.addingTimeInterval(offset), temperatures: [
            TemperatureSensor(id: "cpu", name: "CPU", group: .cpu, celsius: temperature)
        ], fans: [Fan(id: 0, rpm: temperature == nil ? nil : 0)], reportedFanCount: 1,
                 cpuUsagePercent: cpu, gpuUsagePercent: gpu)
    }
    func testLongRangesUseMeansWithoutFillingUnavailableBuckets() {
        var history = History()
        history.append(snapshot(0, temperature: 40, cpu: 20))
        history.append(snapshot(10, temperature: 60, cpu: 80))
        history.append(snapshot(70, temperature: nil))
        let hour = history.samples(in: .hour, now: epoch.addingTimeInterval(70))
        XCTAssertEqual(hour.count, 2)
        XCTAssertEqual(hour[0].temperatures[0].celsius, 50)
        XCTAssertEqual(hour[0].cpuUsagePercent, 50)
        XCTAssertEqual(hour[0].fans[0].rpm, 0)
        XCTAssertNil(hour[1].temperatures[0].celsius)
        XCTAssertNil(hour[1].fans[0].rpm)
        XCTAssertNil(hour[1].cpuUsagePercent)
    }
    func testSevenDayRetentionAndStorageBounds() {
        var history = History()
        // Eight days, one sample per minute: all tiers must remain bounded.
        for minute in 0...(8 * 24 * 60) { history.append(snapshot(Double(minute * 60))) }
        let now = epoch.addingTimeInterval(8 * 24 * 60 * 60)
        XCTAssertLessThanOrEqual(history.samples.count, 901)
        XCTAssertLessThanOrEqual(history.samples(in: .hour, now: now).count, 61)
        XCTAssertLessThanOrEqual(history.samples(in: .day, now: now).count, 289)
        let week = history.samples(in: .week, now: now)
        XCTAssertLessThanOrEqual(week.count, 337)
        XCTAssertGreaterThan(week.count, 330)
        XCTAssertTrue(week.allSatisfy { $0.date >= now.addingTimeInterval(-604800) })
    }
    func testRoundTripAndExpiredArchive() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = HistoryStore(url: folder.appendingPathComponent("history.plist"))
        var history = History()
        history.append(snapshot(0, temperature: 42, cpu: 12, gpu: 24))
        history.append(snapshot(3600, temperature: 66, cpu: 50, gpu: nil))
        let now = epoch.addingTimeInterval(3600)
        try store.save(history, now: now)
        let restored = try store.load(now: now)
        XCTAssertEqual(restored.samples.count, 1)
        XCTAssertEqual(restored.samples.first?.cpuUsagePercent, 50)
        XCTAssertNil(restored.samples.first?.gpuUsagePercent)
        XCTAssertEqual(restored.samples(in: .week, now: now).count, 2)
        XCTAssertEqual(restored.csv(range: .week, now: now), history.csv(range: .week, now: now))
        let expired = try store.load(now: now.addingTimeInterval(8 * 24 * 60 * 60))
        XCTAssertTrue(expired.samples.isEmpty)
        XCTAssertTrue(expired.samples(in: .week, now: now.addingTimeInterval(8 * 24 * 60 * 60)).isEmpty)
    }
    func testMissingLoadFieldsDecodeAsUnavailable() throws {
        let data = try JSONEncoder().encode(snapshot(0, temperature: 55))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "cpuUsagePercent"); json.removeValue(forKey: "gpuUsagePercent")
        let restored = try JSONDecoder().decode(Snapshot.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(restored.cpuUsagePercent); XCTAssertNil(restored.gpuUsagePercent)
        XCTAssertEqual(restored.temperatures.first?.celsius, 55)
    }
    func testMissingCorruptAndUnsupportedArchive() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("history.plist"), store = HistoryStore(url: url)
        XCTAssertTrue(try store.load(now: epoch).samples.isEmpty)
        try Data("corrupt".utf8).write(to: url)
        XCTAssertThrowsError(try store.load(now: epoch)) { error in
            guard case HistoryStoreError.invalidArchive = error else { return XCTFail("Unexpected error: \(error)") }
        }
        try store.save(History(), now: epoch)
        var archive = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
        archive["version"] = 99
        try PropertyListSerialization.data(fromPropertyList: archive, format: .binary, options: 0).write(to: url)
        XCTAssertThrowsError(try store.load(now: epoch)) { error in
            guard case HistoryStoreError.unsupportedVersion(99) = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }
    func testCSVIncludesLoadAndSelectedRangeOnly() {
        var history = History()
        history.append(snapshot(0, cpu: 10, gpu: nil))
        history.append(snapshot(3600, cpu: 25, gpu: 75))
        let csv = history.csv(range: .fifteenMinutes, now: epoch.addingTimeInterval(3600))
        XCTAssertTrue(csv.contains("cpu,load,25.0,%"))
        XCTAssertTrue(csv.contains("gpu,load,75.0,%"))
        XCTAssertFalse(csv.contains("cpu,load,10.0,%"))
    }
    func testLargeSensorCatalogArchiveStaysCompact() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("history.plist"), store = HistoryStore(url: url)
        let sensors = (0..<200).map { TemperatureSensor(id: "sensor-\($0)", name: "Sensor \($0)", group: .other, celsius: 40 + Double($0 % 30)) }
        var history = History()
        for halfHour in 0...336 {
            history.append(Snapshot(date: epoch.addingTimeInterval(Double(halfHour * 1800)), temperatures: sensors))
        }
        let end = epoch.addingTimeInterval(604800)
        // A dense recent window coexists with the coarse seven-day archive.
        for second in 1...901 { history.append(Snapshot(date: end.addingTimeInterval(Double(second)), temperatures: sensors)) }
        let now = end.addingTimeInterval(901)
        try store.save(history, now: now)
        let bytes = try Data(contentsOf: url).count
        XCTAssertLessThan(bytes, 16 * 1024 * 1024)
        let restored = try store.load(now: now)
        XCTAssertEqual(restored.samples.count, 901)
        XCTAssertEqual(restored.samples.last?.temperatures.count, 200)
        XCTAssertGreaterThan(restored.samples(in: .week, now: now).count, 330)
    }
}
