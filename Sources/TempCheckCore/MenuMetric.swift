import Foundation

public enum MenuMetric: String, CaseIterable {
    case hottest, cpu, gpu, battery, fan
    public var label: String {
        switch self {
        case .hottest: return "Najcieplejszy czujnik"
        case .cpu: return "Temperatura CPU"
        case .gpu: return "Temperatura GPU"
        case .battery: return "Temperatura baterii"
        case .fan: return "Obroty wentylatora"
        }
    }
    public var symbol: String { self == .fan ? "fanblades" : "thermometer" }
    public func reading(snapshot: Snapshot, unit: TemperatureUnit, fanID: Int) -> MenuReading {
        if self == .fan {
            let fan = snapshot.fans.first { $0.id == fanID }
            return MenuReading(text: fan?.rpm.map { "\(Int($0.rounded())) RPM" } ?? "— RPM", description: "Wentylator \(fanID + 1)")
        }
        let group: SensorGroup?
        switch self { case .cpu: group = .cpu; case .gpu: group = .gpu; case .battery: group = .battery; default: group = nil }
        let sensor = snapshot.temperatures.filter { $0.celsius != nil && (group == nil || $0.group == group) }.max { $0.celsius! < $1.celsius! }
        let detail = sensor.map { "\($0.name) · \($0.id)" } ?? "Brak odczytu"
        return MenuReading(text: unit.format(sensor?.celsius), description: "\(label) · \(detail)")
    }
}
public struct MenuReading {
    public let text: String
    public let description: String
}
