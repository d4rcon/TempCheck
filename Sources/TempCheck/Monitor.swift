import AppKit
import Combine
import UniformTypeIdentifiers
import TempCheckCore

@MainActor final class Monitor: ObservableObject {
    @Published private(set) var snapshot = Snapshot()
    @Published private(set) var history = History()
    @Published private(set) var busy = false
    @Published private(set) var historyLoading = false
    @Published private(set) var storageIssue: String?
    @Published var paused = false {
        didSet {
            alertPolicy.resetContinuity()
            if paused { saveHistory() } else { resetLoad = true; refresh() }
        }
    }
    @Published var selectedID = ""
    @Published var error: String?
    @Published var interval: Double { didSet { preference(interval, "interval"); schedule() } }
    @Published var unit: TemperatureUnit { didSet { preference(unit.rawValue, "unit") } }
    @Published var menuMetric: MenuMetric { didSet { preference(menuMetric.rawValue, "menuMetric") } }
    @Published var menuFanID: Int { didSet { preference(menuFanID, "menuFanID") } }
    @Published var historyRange: HistoryRange = .fifteenMinutes { didSet { rebuildHistoryView() } }
    @Published private(set) var visibleHistory: [Snapshot] = []
    @Published private(set) var availableTemperatureSensors: [TemperatureSensor] = []
    @Published private(set) var alertsEnabled: Bool
    @Published private(set) var alertSnoozedUntil: Date?
    @Published var alertThreshold: Double {
        didSet {
            preference(alertThreshold, "alertThreshold")
            alertPolicy = ThermalAlertPolicy(thresholdCelsius: alertThreshold)
            if let until = alertSnoozedUntil { alertPolicy.snooze(until: until) }
        }
    }
    let demo: Bool
    let notifications: NotificationService
    let loginItem: LoginItemService
    private let queue = DispatchQueue(label: "TempCheck.sensors", qos: .utility)
    private let reader = SensorReader()
    private let loadReader = SystemLoadReader()
    private let store: HistoryStore
    private var alertPolicy: ThermalAlertPolicy
    private var timer: AnyCancellable?
    private var subscriptions = Set<AnyCancellable>()
    private var sleeping = false
    private var resetLoad = false
    private var lastSave = Date.distantPast
    private var persistenceEnabled = true
    private var observers: [NSObjectProtocol] = []
    var onChange: (() -> Void)?

    init(demo: Bool) {
        self.demo = demo
        let defaults = UserDefaults.standard, saved = UserDefaults.standard.double(forKey: "interval")
        interval = [1.0, 2, 5, 10].contains(saved) ? saved : 2
        unit = TemperatureUnit(rawValue: defaults.string(forKey: "unit") ?? "") ?? .celsius
        menuMetric = MenuMetric(rawValue: defaults.string(forKey: "menuMetric") ?? "") ?? .hottest
        menuFanID = max(0, min(15, defaults.integer(forKey: "menuFanID")))
        let threshold = defaults.double(forKey: "alertThreshold")
        let validatedThreshold = (70...110).contains(threshold) ? threshold : 90
        alertThreshold = validatedThreshold
        alertsEnabled = !demo && defaults.bool(forKey: "alertsEnabled")
        let savedSnooze = defaults.object(forKey: "alertSnoozedUntil") as? Date
        alertSnoozedUntil = savedSnooze
        var policy = ThermalAlertPolicy(thresholdCelsius: validatedThreshold)
        if let until = savedSnooze { policy.snooze(until: until) }
        alertPolicy = policy
        notifications = NotificationService(canUseSystemServices: !demo)
        loginItem = LoginItemService(canUseSystemServices: !demo)
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        store = HistoryStore(url: support.appendingPathComponent("TempCheck/history.plist"))
        notifications.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        loginItem.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.sleeping = true; self.alertPolicy.resetContinuity(); self.saveHistory()
            }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.sleeping = false; self.resetLoad = true; self.alertPolicy.resetContinuity(); self.refresh()
            }
        })
        if demo {
            let now = Date()
            for i in stride(from: 450, through: 0, by: -1) { history.append(DemoReader.sample(at: now.addingTimeInterval(-Double(i) * 2))) }
            snapshot = history.samples.last ?? Snapshot(); selectedID = "demo-cpu"; rebuildHistoryView(); schedule(); refresh()
        } else { restoreHistory() }
    }
    deinit { for token in observers { NSWorkspace.shared.notificationCenter.removeObserver(token) } }
    private func preference(_ value: Any?, _ key: String) { if !demo { UserDefaults.standard.set(value, forKey: key) } }
    private func schedule() {
        timer = Timer.publish(every: interval, tolerance: interval * 0.15, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self, !self.paused, !self.sleeping else { return }; self.refresh()
        }
    }
    private func restoreHistory() {
        historyLoading = true
        let store = store
        queue.async { [weak self] in
            let result = Result { try store.load() }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch result {
                case .success(let history): self.history = history
                case .failure:
                    self.persistenceEnabled = false
                    self.storageIssue = "Nie można wczytać historii. Zapis wstrzymano, aby zachować istniejący plik. Bieżące pomiary nadal działają."
                }
                self.rebuildHistoryView(); self.historyLoading = false; self.schedule(); self.refresh()
            }
        }
    }
    func refresh() {
        guard !busy, !sleeping, !historyLoading else { return }
        busy = true
        let demo = demo, reader = reader, loadReader = loadReader, reset = resetLoad
        resetLoad = false
        queue.async { [weak self] in
            if reset { loadReader.reset() }
            let sensors = demo ? DemoReader.sample() : reader.sample()
            let load = demo ? nil : loadReader.sample()
            let result = Snapshot(date: sensors.date, temperatures: sensors.temperatures, fans: sensors.fans,
                                  reportedFanCount: sensors.reportedFanCount, thermal: sensors.thermal, issue: sensors.issue,
                                  cpuUsagePercent: demo ? 34 + sin(sensors.date.timeIntervalSince1970 / 12) * 12 : load?.cpuUsagePercent,
                                  gpuUsagePercent: demo ? 21 + sin(sensors.date.timeIntervalSince1970 / 12) * 8 : load?.gpuUsagePercent)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.snapshot = result; self.history.append(result); self.rebuildHistoryView(); self.busy = false
                if !self.availableTemperatureSensors.contains(where: { $0.id == self.selectedID }) {
                    self.selectedID = result.hottest?.id ?? self.availableTemperatureSensors.first?.id ?? ""
                }
                self.evaluateAlert(result)
                if Date().timeIntervalSince(self.lastSave) >= 60 { self.saveHistory() }
                self.onChange?()
            }
        }
    }
    private func rebuildHistoryView() {
        visibleHistory = history.samples(in: historyRange)
        var sensors = Dictionary(uniqueKeysWithValues: snapshot.temperatures.map { ($0.id, $0) })
        for sample in visibleHistory.reversed() {
            for sensor in sample.temperatures where sensors[sensor.id] == nil { sensors[sensor.id] = sensor }
        }
        availableTemperatureSensors = sensors.values.sorted { $0.id < $1.id }
    }
    var selected: TemperatureSensor? { snapshot.temperatures.first { $0.id == selectedID } }
    var menuReading: MenuReading { menuMetric.reading(snapshot: snapshot, unit: unit, fanID: menuFanID) }
    var selectedHistoryValues: [Double] { visibleHistory.compactMap { $0.temperatures.first { $0.id == selectedID }?.celsius } }
    func setAlertsEnabled(_ enabled: Bool) async {
        guard !demo else { return }
        if enabled {
            let granted = await notifications.requestPermission()
            if !granted { alertsEnabled = false; preference(false, "alertsEnabled"); return }
        }
        alertsEnabled = enabled; preference(enabled, "alertsEnabled"); alertPolicy.resetContinuity()
    }
    func snoozeAlerts() {
        let until = Date().addingTimeInterval(3600)
        alertSnoozedUntil = until; alertPolicy.snooze(until: until); preference(until, "alertSnoozedUntil")
    }
    func resumeAlerts() { alertSnoozedUntil = nil; alertPolicy.snooze(until: .distantPast); preference(nil, "alertSnoozedUntil") }
    private func evaluateAlert(_ sample: Snapshot) {
        let sensor = sample.temperatures.filter { ($0.group == .cpu || $0.group == .gpu) && $0.celsius != nil }.max { $0.celsius! < $1.celsius! }
        if alertPolicy.evaluate(temp: sensor?.celsius, at: sample.date,
                                enabled: alertsEnabled && notifications.canSend && !demo && !paused && !sleeping,
                                continuityInterval: max(15, interval * 2.5)), let celsius = sensor?.celsius {
            notifications.deliverHighTemperature(celsius: celsius, sensorName: sensor?.name ?? "Czujnik")
        }
    }
    func saveHistory(completion: (() -> Void)? = nil) {
        guard !demo, !historyLoading, persistenceEnabled else {
            if let completion { DispatchQueue.main.async { completion() } }
            return
        }
        lastSave = Date()
        let store = store, history = history
        queue.async { [weak self] in
            let failed: Bool
            do { try store.save(history); failed = false } catch { failed = true }
            DispatchQueue.main.async { [weak self] in
                self?.storageIssue = failed ? "Nie udało się zapisać historii na dysku. Bieżące pomiary pozostają dostępne." : nil
                completion?()
            }
        }
    }
    func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "TempCheck-\(ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let content = history.csv(range: historyRange)
        queue.async { [weak self] in
            do { try content.write(to: url, atomically: true, encoding: .utf8) }
            catch { DispatchQueue.main.async { self?.error = "Nie udało się zapisać CSV: \(error.localizedDescription)" } }
        }
    }
}
