import Foundation
import CSensors

/// All mutable state and SMC operations are protected by lock. No SMC writes.
public final class SensorReader: @unchecked Sendable {
    private let lock = NSLock()
    private var connection: UInt32 = 0
    private var keys: [String] = []
    private var lastScan = Date.distantPast
    private var scanIssue: String?
    public init() {}
    deinit { tc_close(connection) }

    private func number(_ key: String) -> Double? {
        var value = TCValue(), result: Double = 0
        guard key.withCString({ tc_read(connection, $0, &value) }) == 0, tc_decode(&value, &result) else { return nil }
        return result
    }
    private func discover() {
        var found = Set<String>()
        scanIssue = nil
        if let count = number("#KEY"), count >= 0, count <= 20000, count.rounded() == count {
            for index in 0..<Int(count) {
                var buffer = [CChar](repeating: 0, count: 5)
                if tc_key_at(connection, UInt32(index), &buffer) == 0 {
                    let key = String(cString: buffer)
                    if key.hasPrefix("T"), ReadingRules.temperature(number(key)) != nil { found.insert(key) }
                }
            }
        } else { scanIssue = "Nie udało się pobrać listy czujników. Dostępne są tylko rozpoznane klucze." }
        // Common documented-by-community keys also work if enumeration is unavailable.
        for key in ["TC0P", "TC0D", "TC0E", "TC0F", "TG0P", "TG0D", "TB0T", "TB1T", "TB2T", "Tp01", "Tp05", "Tp09", "Tp0D", "Te05", "Te0L", "Tg0f", "Tg0j"] {
            if ReadingRules.temperature(number(key)) != nil { found.insert(key) }
        }
        keys = found.sorted(); lastScan = Date()
    }
    public func sample() -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        if connection == 0 {
            let status = tc_open(&connection)
            guard status == 0 else {
                return Snapshot(thermal: .current, issue: "Brak dostępu do czujników SMC (kod \(status)). Odczyt temperatur i RPM jest niedostępny.")
            }
        }
        if Date().timeIntervalSince(lastScan) > 60 { discover() }
        let temperatures = keys.map { key -> TemperatureSensor in
            let label = Self.label(key)
            return TemperatureSensor(id: key, name: label.0, group: label.1, celsius: ReadingRules.temperature(number(key)))
        }
        let count = ReadingRules.fanCount(number("FNum"))
        let fans: [Fan] = (0..<(count ?? 0)).map { id in
            let prefix = "F" + String(id, radix: 16).uppercased()
            return Fan(id: id, rpm: ReadingRules.rpm(number(prefix + "Ac")),
                       minimum: ReadingRules.rpm(number(prefix + "Mn")), maximum: ReadingRules.rpm(number(prefix + "Mx")))
        }
        let issue: String?
        if !temperatures.contains(where: { $0.celsius != nil }) { issue = "SMC nie udostępnił poprawnych odczytów temperatur. Stan cieplny macOS pozostaje dostępny." }
        else if count == nil { issue = "Temperatury są dostępne. Nie udało się ustalić liczby wentylatorów." }
        else { issue = scanIssue }
        if !temperatures.contains(where: { $0.celsius != nil }), count == nil {
            tc_close(connection); connection = 0; lastScan = .distantPast
        }
        return Snapshot(temperatures: temperatures, fans: fans, reportedFanCount: count, thermal: .current, issue: issue)
    }
    static func label(_ key: String) -> (String, SensorGroup) {
        let known: [String: (String, SensorGroup)] = [
            "TC0P": ("CPU · obudowa układu", .cpu), "TC0D": ("CPU · dioda", .cpu),
            "TC0E": ("CPU · czujnik E", .cpu), "TC0F": ("CPU · czujnik F", .cpu),
            "TG0P": ("GPU · obudowa układu", .gpu), "TG0D": ("GPU · dioda", .gpu),
            "TB0T": ("Bateria · czujnik 1", .battery), "TB1T": ("Bateria · czujnik 2", .battery), "TB2T": ("Bateria · czujnik 3", .battery)
        ]
        if let entry = known[key] { return entry }
        #if arch(arm64)
        // Community SMC conventions group zones, without claiming exact physical cores.
        // Tf is shared between CPU and GPU, so match only confirmed keys in that family.
        if key.hasPrefix("Tp") || key.hasPrefix("Te") ||
            ["Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E", "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E"].contains(key) {
            return ("CPU · strefa \(key)", .cpu)
        }
        if key.hasPrefix("Tg") || ["Tf14", "Tf18", "Tf19", "Tf1A", "Tf24", "Tf28", "Tf29", "Tf2A"].contains(key) {
            return ("GPU · strefa \(key)", .gpu)
        }
        #endif
        return ("Czujnik \(key)", .other)
    }
}

public enum DemoReader {
    public static func sample(at date: Date = Date()) -> Snapshot {
        let wave = sin(date.timeIntervalSince1970 / 12)
        return Snapshot(date: date, temperatures: [
            TemperatureSensor(id: "demo-cpu", name: "CPU · przykład", group: .cpu, celsius: 56 + wave * 8),
            TemperatureSensor(id: "demo-gpu", name: "GPU · przykład", group: .gpu, celsius: 49 + wave * 5),
            TemperatureSensor(id: "demo-battery", name: "Bateria · przykład", group: .battery, celsius: 32 + wave)
        ], fans: [Fan(id: 0, rpm: 2100 + wave * 400, minimum: 1200, maximum: 6500),
                  Fan(id: 1, rpm: 2000 + wave * 300, minimum: 1200, maximum: 6500)], reportedFanCount: 2, thermal: .nominal)
    }
}
