import AppKit
import SwiftUI
import Combine
import TempCheckCore

@main enum TempCheckMain {
    @MainActor static func main() {
        let arguments = CommandLine.arguments
        if arguments.contains("--diagnose") {
            let sensors = SensorReader().sample(), loadReader = SystemLoadReader()
            _ = loadReader.sample()
            Thread.sleep(forTimeInterval: 0.25)
            let load = loadReader.sample()
            let snapshot = Snapshot(date: sensors.date, temperatures: sensors.temperatures, fans: sensors.fans,
                                    reportedFanCount: sensors.reportedFanCount, thermal: sensors.thermal, issue: sensors.issue,
                                    cpuUsagePercent: load.cpuUsagePercent, gpuUsagePercent: load.gpuUsagePercent)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(snapshot), let text = String(data: data, encoding: .utf8) { print(text) }
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate(demo: arguments.contains("--demo") || arguments.contains("--render-preview"))
        app.delegate = delegate
        if let index = arguments.firstIndex(of: "--render-preview"), arguments.count > index + 1 {
            delegate.prepareWindow()
            if arguments.contains("--dark") { delegate.window?.appearance = NSAppearance(named: .darkAqua) }
            guard let view = delegate.window?.contentView else { return }
            view.layoutSubtreeIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else { return }
            do { try data.write(to: URL(fileURLWithPath: arguments[index + 1])); print("Saved preview") }
            catch { fputs("\(error)\n", stderr) }
            return
        }
        app.setActivationPolicy(.regular)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let monitor: Monitor
    var window: NSWindow?
    private var statusItem: NSStatusItem?
    private var changes: AnyCancellable?
    private var terminating = false
    init(demo: Bool) { monitor = Monitor(demo: demo); super.init() }
    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = status
        status.button?.image = NSImage(systemSymbolName: "thermometer", accessibilityDescription: "TempCheck")
        status.button?.imagePosition = .imageLeading
        status.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let menu = NSMenu(); menu.delegate = self; status.menu = menu
        changes = monitor.objectWillChange.debounce(for: .milliseconds(80), scheduler: RunLoop.main).sink { [weak self] _ in self?.updateStatus() }
        updateStatus()
        if LoginItemService.wasLaunchedAtLogin { NSApp.setActivationPolicy(.accessory) }
        else { showWindow() }
    }
    func prepareWindow() {
        guard window == nil else { return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1020, height: 800),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "TempCheck"
        window.minSize = NSSize(width: 930, height: 720)
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: Dashboard(monitor: monitor, initialTab: CommandLine.arguments.contains("--settings-preview") ? 2 : 0))
        window.center(); self.window = window
    }
    private func installMainMenu() {
        let menu = NSMenu(), appItem = NSMenuItem(), appMenu = NSMenu()
        menu.addItem(appItem); appItem.submenu = appMenu
        add(appMenu, "O TempCheck", #selector(about))
        appMenu.addItem(.separator())
        add(appMenu, "Pokaż TempCheck", #selector(showWindow), key: "0")
        add(appMenu, "Zamknij TempCheck", #selector(quit), key: "q")
        let editItem = NSMenuItem(), edit = NSMenu(title: "Edycja")
        menu.addItem(editItem); editItem.submenu = edit
        for (title, action, key) in [("Kopiuj", #selector(NSText.copy(_:)), "c"), ("Wklej", #selector(NSText.paste(_:)), "v"), ("Zaznacz wszystko", #selector(NSText.selectAll(_:)), "a")] {
            edit.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        NSApp.mainMenu = menu
    }
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector?, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = action == nil ? nil : self
        if action == nil { item.isEnabled = false }; menu.addItem(item)
    }
    private func updateStatus() {
        let prefix = monitor.demo ? "DEMO " : ""
        statusItem?.button?.image = NSImage(systemSymbolName: monitor.menuMetric.symbol, accessibilityDescription: "TempCheck")
        statusItem?.button?.title = " \(prefix)\(monitor.menuReading.text)\(monitor.paused ? " Ⅱ" : "")"
        statusItem?.button?.toolTip = "TempCheck · \(monitor.menuReading.description)\(monitor.paused ? " · pomiar wstrzymany" : "")"
    }
    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        add(menu, monitor.demo ? "TempCheck — DEMO" : "TempCheck", nil)
        add(menu, "Stan cieplny: \(monitor.snapshot.thermal.rawValue)", nil)
        if let cpu = monitor.snapshot.cpuUsagePercent { add(menu, "Obciążenie CPU: \(Int(cpu.rounded()))%", nil) }
        if let gpu = monitor.snapshot.gpuUsagePercent { add(menu, "Obciążenie GPU: \(Int(gpu.rounded()))%", nil) }
        if let hottest = monitor.snapshot.hottest { add(menu, "\(hottest.name): \(monitor.unit.format(hottest.celsius))", nil) }
        if monitor.snapshot.reportedFanCount == 0 { add(menu, "SMC: brak wentylatorów", nil) }
        else if monitor.snapshot.fans.isEmpty { add(menu, "Wentylatory: brak danych", nil) }
        for fan in monitor.snapshot.fans { add(menu, "Wentylator \(fan.id + 1): \(fan.rpm.map { String(Int($0.rounded())) } ?? "—") RPM", nil) }
        if monitor.snapshot.issue != nil { add(menu, "Część odczytów jest niedostępna", nil) }
        menu.addItem(.separator())
        add(menu, "Pokaż okno…", #selector(showWindow))
        add(menu, monitor.paused ? "Wznów pomiary" : "Wstrzymaj pomiary", #selector(togglePause))
        add(menu, "Odśwież teraz", #selector(refresh))
        add(menu, "Eksport CSV…", #selector(export))
        menu.addItem(.separator()); add(menu, "Zamknij TempCheck", #selector(quit), key: "q")
    }
    @objc func showWindow() { NSApp.setActivationPolicy(.regular); prepareWindow(); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc private func refresh() { monitor.refresh() }
    @objc private func togglePause() { monitor.paused.toggle() }
    @objc private func export() { showWindow(); monitor.exportCSV() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func about() { NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "TempCheck", .applicationVersion: "0.2.0", .credits: NSAttributedString(string: "Temperatura i chłodzenie Twojego Maca.\nDane przetwarzane lokalnie.")]) }
    func applicationDidBecomeActive(_ notification: Notification) { monitor.loginItem.refresh(); monitor.notifications.refreshAuthorization() }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if !terminating {
            terminating = true
            monitor.saveHistory { NSApp.reply(toApplicationShouldTerminate: true) }
        }
        return .terminateLater
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
