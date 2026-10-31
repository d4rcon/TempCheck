import Foundation

public enum SensorGroup: String, CaseIterable, Codable, Sendable {
    case cpu = "CPU", gpu = "GPU", battery = "Bateria", other = "Pozostałe"
}
public struct TemperatureSensor: Identifiable, Codable, Sendable {
    public let id: String
    public let name: String
    public let group: SensorGroup
    public let celsius: Double?
    public init(id: String, name: String, group: SensorGroup, celsius: Double?) {
        self.id = id; self.name = name; self.group = group; self.celsius = celsius
    }
}
public struct Fan: Identifiable, Codable, Sendable {
    public let id: Int
    public let rpm: Double?
    public let minimum: Double?
    public let maximum: Double?
    public init(id: Int, rpm: Double?, minimum: Double? = nil, maximum: Double? = nil) {
        self.id = id; self.rpm = rpm; self.minimum = minimum; self.maximum = maximum
    }
}
public enum ThermalLevel: String, Codable, Sendable {
    case nominal = "Normalny", fair = "Podwyższony", serious = "Wysoki", critical = "Krytyczny", unknown = "Nieznany"
    public static var current: Self {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .unknown
        }
    }
}
public struct Snapshot: Codable, Sendable {
    public let date: Date
    public let temperatures: [TemperatureSensor]
    public let fans: [Fan]
    public let reportedFanCount: Int?
    public let thermal: ThermalLevel
    public let issue: String?
    public let cpuUsagePercent: Double?
    public let gpuUsagePercent: Double?
    public init(date: Date = Date(), temperatures: [TemperatureSensor] = [], fans: [Fan] = [],
                reportedFanCount: Int? = nil, thermal: ThermalLevel = .unknown, issue: String? = nil,
                cpuUsagePercent: Double? = nil, gpuUsagePercent: Double? = nil) {
        self.date = date; self.temperatures = temperatures; self.fans = fans
        self.reportedFanCount = reportedFanCount; self.thermal = thermal; self.issue = issue
        self.cpuUsagePercent = cpuUsagePercent; self.gpuUsagePercent = gpuUsagePercent
    }
    public var hottest: TemperatureSensor? { temperatures.filter { $0.celsius != nil }.max { $0.celsius! < $1.celsius! } }
}
public enum ReadingRules {
    // Zero temperature is often an inactive SMC channel; zero RPM is a valid stopped fan.
    public static func temperature(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0, value <= 150 else { return nil }; return value
    }
    public static func rpm(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0, value <= 30000 else { return nil }; return value
    }
    public static func fanCount(_ value: Double?) -> Int? {
        guard let value, value.isFinite, value >= 0, value <= 16, value.rounded() == value else { return nil }; return Int(value)
    }
}
public enum TemperatureUnit: String, CaseIterable {
    case celsius = "°C", fahrenheit = "°F"
    public func convert(_ celsius: Double) -> Double { self == .celsius ? celsius : celsius * 9 / 5 + 32 }
    public func format(_ value: Double?) -> String {
        guard let value else { return "—" }; return String(format: "%.0f %@", convert(value), rawValue)
    }
}
public enum HistoryRange: String, CaseIterable, Codable, Identifiable, Sendable {
    case fifteenMinutes = "15 min", hour = "1 godz.", day = "24 godz.", week = "7 dni"
    public var id: String { rawValue }
    public var label: String { rawValue }
    public var duration: TimeInterval {
        switch self { case .fifteenMinutes: return 900; case .hour: return 3600; case .day: return 86400; case .week: return 604800 }
    }
    /// Longer views show bucket means; unavailable values are excluded from the mean.
    public var bucketDuration: TimeInterval {
        switch self { case .fifteenMinutes: return 1; case .hour: return 60; case .day: return 300; case .week: return 1800 }
    }
}

public struct History: Codable, Sendable {
    public private(set) var samples: [Snapshot] = []
    private var hourly: [HistoryBucket] = []
    private var daily: [HistoryBucket] = []
    private var weekly: [HistoryBucket] = []
    public init() {}
    public mutating func append(_ sample: Snapshot) {
        guard sample.date.timeIntervalSince1970.isFinite else { return }
        samples.append(sample)
        if samples.count > 1, samples[samples.count - 2].date > sample.date { samples.sort { $0.date < $1.date } }
        Self.aggregate(sample, into: &hourly, interval: HistoryRange.hour.bucketDuration)
        Self.aggregate(sample, into: &daily, interval: HistoryRange.day.bucketDuration)
        Self.aggregate(sample, into: &weekly, interval: HistoryRange.week.bucketDuration)
        trim(now: samples.last?.date ?? sample.date)
    }
    /// Discards expired data and bounds every resolution, including after loading an archive.
    public mutating func trim(now: Date = Date()) {
        samples.removeAll { $0.date < now.addingTimeInterval(-900) || $0.date > now.addingTimeInterval(60) }
        if samples.count > 901 { samples.removeFirst(samples.count - 901) }
        Self.prune(&hourly, range: .hour, now: now)
        Self.prune(&daily, range: .day, now: now)
        Self.prune(&weekly, range: .week, now: now)
    }
    public func samples(in range: HistoryRange, now: Date = Date()) -> [Snapshot] {
        let source: [Snapshot]
        switch range {
        case .fifteenMinutes: source = samples
        case .hour: source = hourly.map(\.snapshot)
        case .day: source = daily.map(\.snapshot)
        case .week: source = weekly.map(\.snapshot)
        }
        let cutoff = now.addingTimeInterval(-range.duration)
        return source.filter { $0.date >= cutoff && $0.date <= now }
    }
    public func values(sensorID: String) -> [Double] {
        samples.compactMap { $0.temperatures.first { $0.id == sensorID }?.celsius }
    }
    public func values(sensorID: String, range: HistoryRange, now: Date = Date()) -> [Double] {
        samples(in: range, now: now).compactMap { $0.temperatures.first { $0.id == sensorID }?.celsius }
    }
    public func csv() -> String { Self.csv(samples) }
    public func csv(range: HistoryRange, now: Date = Date()) -> String { Self.csv(samples(in: range, now: now)) }
    private static func csv(_ samples: [Snapshot]) -> String {
        var rows = ["timestamp,sensor_id,kind,value,unit"]
        let formatter = ISO8601DateFormatter()
        for sample in samples {
            let date = formatter.string(from: sample.date)
            for sensor in sample.temperatures {
                rows.append("\(date),\(Self.escape(sensor.id)),temperature,\(sensor.celsius.map { String($0) } ?? ""),C")
            }
            for fan in sample.fans { rows.append("\(date),fan\(fan.id),fan,\(fan.rpm.map { String($0) } ?? ""),RPM") }
            rows.append("\(date),cpu,load,\(sample.cpuUsagePercent.map { String($0) } ?? ""),%")
            rows.append("\(date),gpu,load,\(sample.gpuUsagePercent.map { String($0) } ?? ""),%")
        }
        return rows.joined(separator: "\r\n") + "\r\n"
    }
    private static func escape(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
    private static func aggregate(_ sample: Snapshot, into buckets: inout [HistoryBucket], interval: TimeInterval) {
        let start = floor(sample.date.timeIntervalSince1970 / interval) * interval
        if let index = buckets.lastIndex(where: { $0.start == start }) { buckets[index].append(sample) }
        else {
            var bucket = HistoryBucket(start: start, latest: sample)
            bucket.append(sample); buckets.append(bucket)
            if buckets.count > 1, buckets[buckets.count - 2].start > start { buckets.sort { $0.start < $1.start } }
        }
    }
    private static func prune(_ buckets: inout [HistoryBucket], range: HistoryRange, now: Date) {
        let cutoff = now.addingTimeInterval(-range.duration)
        buckets.removeAll { $0.latestDate < cutoff || $0.latestDate > now.addingTimeInterval(60) }
        let maximum = Int(range.duration / range.bucketDuration) + 1
        if buckets.count > maximum { buckets.removeFirst(buckets.count - maximum) }
    }
}

private struct HistoryMean: Codable, Sendable {
    var sum: Double = 0
    var count: Int = 0
    mutating func add(_ value: Double?) {
        guard let value, value.isFinite else { return }
        sum += value; count += 1
    }
    var value: Double? { count > 0 && sum.isFinite ? sum / Double(count) : nil }
}

private struct HistoryTemperature: Codable, Sendable {
    var name: String
    var group: SensorGroup
    var mean = HistoryMean()
}

private struct HistoryFan: Codable, Sendable {
    var minimum: Double?
    var maximum: Double?
    var mean = HistoryMean()
}

private struct HistoryBucket: Codable, Sendable {
    let start: TimeInterval
    var latestDate: Date
    var reportedFanCount: Int?
    var thermal: ThermalLevel
    var issue: String?
    var temperatures: [String: HistoryTemperature] = [:]
    var fans: [Int: HistoryFan] = [:]
    var cpu = HistoryMean()
    var gpu = HistoryMean()

    init(start: TimeInterval, latest: Snapshot) {
        self.start = start; latestDate = latest.date
        reportedFanCount = latest.reportedFanCount; thermal = latest.thermal; issue = latest.issue
    }
    mutating func append(_ sample: Snapshot) {
        if sample.date >= latestDate {
            latestDate = sample.date; reportedFanCount = sample.reportedFanCount
            thermal = sample.thermal; issue = sample.issue
        }
        for sensor in sample.temperatures {
            var entry = temperatures[sensor.id] ?? HistoryTemperature(name: sensor.name, group: sensor.group)
            entry.mean.add(ReadingRules.temperature(sensor.celsius)); temperatures[sensor.id] = entry
        }
        for fan in sample.fans {
            var entry = fans[fan.id] ?? HistoryFan(minimum: fan.minimum, maximum: fan.maximum)
            entry.minimum = fan.minimum; entry.maximum = fan.maximum
            entry.mean.add(ReadingRules.rpm(fan.rpm)); fans[fan.id] = entry
        }
        cpu.add(Self.load(sample.cpuUsagePercent)); gpu.add(Self.load(sample.gpuUsagePercent))
    }
    private static func load(_ value: Double?) -> Double? {
        guard let value, value.isFinite, (0...100).contains(value) else { return nil }; return value
    }
    var snapshot: Snapshot {
        Snapshot(date: latestDate, temperatures: temperatures.keys.sorted().compactMap { key in
            guard let value = temperatures[key] else { return nil }
            return TemperatureSensor(id: key, name: value.name, group: value.group, celsius: value.mean.value)
        }, fans: fans.keys.sorted().compactMap { key in
            guard let value = fans[key] else { return nil }
            return Fan(id: key, rpm: value.mean.value, minimum: value.minimum, maximum: value.maximum)
        }, reportedFanCount: reportedFanCount, thermal: thermal, issue: issue,
                 cpuUsagePercent: cpu.value, gpuUsagePercent: gpu.value)
    }
}
