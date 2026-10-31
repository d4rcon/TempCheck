import AppKit
import Combine
import UniformTypeIdentifiers
import TempCheckCore

@MainActor final class Monitor: ObservableObject {
    @Published private(set) var snapshot = Snapshot()
    @Published private(set) var history = History()
    @Published private(set) var busy = false
    @Published var paused = false { didSet { if !paused { refresh() } } }
    @Published var selectedID: String = ""
    @Published var error: String?
    @Published var interval: Double { didSet { UserDefaults.standard.set(interval, forKey: "interval"); schedule() } }
    @Published var unit: TemperatureUnit { didSet { UserDefaults.standard.set(unit.rawValue, forKey: "unit") } }
    let demo: Bool
    private let queue = DispatchQueue(label: "TempCheck.sensors", qos: .utility)
    private let reader = SensorReader()
    private var timer: AnyCancellable?
    private var sleeping = false
    private var sleepObservers: [NSObjectProtocol] = []
    var onChange: (() -> Void)?

    init(demo: Bool) {
        self.demo = demo
        let saved = UserDefaults.standard.double(forKey: "interval")
        interval = [1.0, 2, 5, 10].contains(saved) ? saved : 2
        unit = TemperatureUnit(rawValue: UserDefaults.standard.string(forKey: "unit") ?? "") ?? .celsius
        let center = NSWorkspace.shared.notificationCenter
        sleepObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.sleeping = true }
        })
        sleepObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.sleeping = false; self?.refresh() }
        })
        if demo {
            let now = Date()
            for i in stride(from: 150, through: 0, by: -1) { history.append(DemoReader.sample(at: now.addingTimeInterval(-Double(i) * 6))) }
            snapshot = history.samples.last ?? Snapshot()
            selectedID = "demo-cpu"
        }
        schedule(); refresh()
    }
    deinit { for token in sleepObservers { NSWorkspace.shared.notificationCenter.removeObserver(token) } }
    private func schedule() {
        timer = Timer.publish(every: interval, tolerance: interval * 0.15, on: .main, in: .common)
            .autoconnect().sink { [weak self] _ in
                guard let self, !self.paused, !self.sleeping else { return }; self.refresh()
            }
    }
    func refresh() {
        guard !busy, !sleeping else { return }
        busy = true
        let demo = demo, reader = reader
        queue.async { [weak self] in
            let result = demo ? DemoReader.sample() : reader.sample()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.snapshot = result; self.history.append(result); self.busy = false
                if !result.temperatures.contains(where: { $0.id == self.selectedID }) {
                    self.selectedID = result.hottest?.id ?? result.temperatures.first?.id ?? ""
                }
                self.onChange?()
            }
        }
    }
    var selected: TemperatureSensor? { snapshot.temperatures.first { $0.id == selectedID } }
    func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "TempCheck-\(ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-" )).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try history.csv().write(to: url, atomically: true, encoding: .utf8) }
        catch { self.error = "Nie udało się zapisać CSV: \(error.localizedDescription)" }
    }
}
