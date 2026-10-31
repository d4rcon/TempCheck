import Foundation

public enum SensorGroup: String, CaseIterable, Codable {
    case cpu = "CPU", gpu = "GPU", battery = "Bateria", other = "Pozostałe"
}
public struct TemperatureSensor: Identifiable, Codable {
    public let id: String
    public let name: String
    public let group: SensorGroup
    public let celsius: Double?
    public init(id: String, name: String, group: SensorGroup, celsius: Double?) {
        self.id = id; self.name = name; self.group = group; self.celsius = celsius
    }
}
public struct Fan: Identifiable, Codable {
    public let id: Int
    public let rpm: Double?
    public let minimum: Double?
    public let maximum: Double?
    public init(id: Int, rpm: Double?, minimum: Double? = nil, maximum: Double? = nil) {
        self.id = id; self.rpm = rpm; self.minimum = minimum; self.maximum = maximum
    }
}
public enum ThermalLevel: String, Codable {
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
public struct Snapshot: Codable {
    public let date: Date
    public let temperatures: [TemperatureSensor]
    public let fans: [Fan]
    public let reportedFanCount: Int?
    public let thermal: ThermalLevel
    public let issue: String?
    public init(date: Date = Date(), temperatures: [TemperatureSensor] = [], fans: [Fan] = [],
                reportedFanCount: Int? = nil, thermal: ThermalLevel = .unknown, issue: String? = nil) {
        self.date = date; self.temperatures = temperatures; self.fans = fans
        self.reportedFanCount = reportedFanCount; self.thermal = thermal; self.issue = issue
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
public struct History {
    public private(set) var samples: [Snapshot] = []
    public init() {}
    public mutating func append(_ sample: Snapshot) {
        samples.append(sample)
        let cutoff = sample.date.addingTimeInterval(-900)
        samples.removeAll { $0.date < cutoff }
        if samples.count > 901 { samples.removeFirst(samples.count - 901) }
    }
    public func values(sensorID: String) -> [Double] {
        samples.compactMap { $0.temperatures.first { $0.id == sensorID }?.celsius }
    }
    public func csv() -> String {
        var rows = ["timestamp,sensor_id,kind,value,unit"]
        let formatter = ISO8601DateFormatter()
        for sample in samples {
            let date = formatter.string(from: sample.date)
            for sensor in sample.temperatures {
                rows.append("\(date),\(Self.escape(sensor.id)),temperature,\(sensor.celsius.map { String($0) } ?? ""),C")
            }
            for fan in sample.fans { rows.append("\(date),fan\(fan.id),fan,\(fan.rpm.map { String($0) } ?? ""),RPM") }
        }
        return rows.joined(separator: "\r\n") + "\r\n"
    }
    private static func escape(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
}
