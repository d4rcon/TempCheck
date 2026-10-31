import AppKit
import Combine
import CoreServices
import ServiceManagement
@preconcurrency import UserNotifications

enum NotificationPermission {
    case unavailable, notDetermined, denied, authorized
}

@MainActor final class NotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var permission: NotificationPermission = .unavailable
    @Published private(set) var statusText = ""
    @Published private(set) var error: String?
    @Published private(set) var requesting = false
    private let canUseSystemServices: Bool
    private let isApplicationBundle: Bool

    var canSend: Bool { permission == .authorized && canUseSystemServices && isApplicationBundle }

    init(canUseSystemServices: Bool = true) {
        self.canUseSystemServices = canUseSystemServices
        isApplicationBundle = Bundle.main.bundleURL.pathExtension.lowercased() == "app" && Bundle.main.bundleIdentifier != nil
        super.init()
        guard canUseSystemServices else {
            statusText = "Powiadomienia są wyłączone w trybie demonstracyjnym."
            return
        }
        guard isApplicationBundle else {
            statusText = "Powiadomienia są dostępne po uruchomieniu TempCheck.app."
            return
        }
        UNUserNotificationCenter.current().delegate = self
        refreshAuthorization()
    }

    /// Reads existing permission only. Does not show a system permission prompt.
    func refreshAuthorization() {
        guard canUseSystemServices, isApplicationBundle else { return }
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let status = settings.authorizationStatus
            Task { @MainActor [weak self] in self?.apply(status) }
        }
    }

    /// Invoke only from the user's permission button.
    @discardableResult func requestPermission() async -> Bool {
        guard canUseSystemServices, isApplicationBundle, !requesting else { return false }
        requesting = true; error = nil
        defer { requesting = false }
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            apply(settings.authorizationStatus)
            return granted && canSend
        } catch {
            self.error = "Nie udało się włączyć powiadomień: \(error.localizedDescription)"
            refreshAuthorization()
            return false
        }
    }

    func deliverHighTemperature(celsius: Double, sensorName: String) {
        guard canSend, celsius.isFinite else { return }
        let content = UNMutableNotificationContent()
        content.title = "TempCheck · wysoka temperatura"
        content.body = "\(sensorName): \(String(format: "%.0f", celsius)) °C. Temperatura utrzymywała się powyżej ustawionego progu."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "TempCheck.highTemperature", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { [weak self] failure in
            guard let failure else { return }
            let message = failure.localizedDescription
            Task { @MainActor [weak self] in self?.error = "Nie udało się dostarczyć powiadomienia: \(message)" }
        }
    }

    func openSettings() {
        guard canUseSystemServices else { return }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            if !NSWorkspace.shared.open(url) { error = "Nie udało się otworzyć ustawień powiadomień macOS." }
        }
    }

    private func apply(_ status: UNAuthorizationStatus) {
        switch status {
        case .authorized, .provisional:
            permission = .authorized; statusText = "Powiadomienia dozwolone."
        case .notDetermined:
            permission = .notDetermined; statusText = "Zezwól na powiadomienia, aby otrzymywać alerty."
        case .denied:
            permission = .denied; statusText = "Powiadomienia zablokowane w ustawieniach macOS."
        @unknown default:
            permission = .unavailable; statusText = "Stan uprawnień do powiadomień jest niedostępny."
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                           willPresent notification: UNNotification,
                                           withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

@MainActor final class LoginItemService: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var statusText = ""
    @Published private(set) var error: String?
    @Published private(set) var changing = false
    private let canUseSystemServices: Bool
    private let isApplicationBundle: Bool

    /// Read during applicationDidFinishLaunching before opening the main window.
    static var wasLaunchedAtLogin: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == kAEOpenApplication else { return false }
        return event.paramDescriptor(forKeyword: keyAELaunchedAsLogInItem) != nil
    }

    var supportsAutomaticRegistration: Bool {
        guard canUseSystemServices, isApplicationBundle else { return false }
        if #available(macOS 13.0, *) { return true }
        return false
    }

    init(canUseSystemServices: Bool = true) {
        self.canUseSystemServices = canUseSystemServices
        isApplicationBundle = Bundle.main.bundleURL.pathExtension.lowercased() == "app" && Bundle.main.bundleIdentifier != nil
        refresh()
    }

    /// Read the operating system's registration state rather than a saved preference.
    func refresh() {
        isEnabled = false
        guard canUseSystemServices else { statusText = "Start przy logowaniu jest wyłączony w trybie demonstracyjnym."; return }
        guard isApplicationBundle else { statusText = "Uruchom TempCheck.app, aby zarządzać startem przy logowaniu."; return }
        guard #available(macOS 13.0, *) else {
            statusText = "Na macOS 12 dodaj TempCheck.app w Preferencjach systemowych → Użytkownicy i grupy → Logowanie."
            return
        }
        switch SMAppService.mainApp.status {
        case .enabled:
            isEnabled = true; statusText = "TempCheck uruchomi się przy logowaniu."
        case .notRegistered:
            statusText = "Start przy logowaniu jest wyłączony."
        case .requiresApproval:
            statusText = "Zatwierdź TempCheck w ustawieniach macOS → Ogólne → Rzeczy otwierane podczas logowania."
        case .notFound:
            statusText = "Nie znaleziono aplikacji. Przenieś TempCheck.app do folderu Aplikacje i uruchom ponownie."
        @unknown default:
            statusText = "Stan startu przy logowaniu jest niedostępny."
        }
    }

    /// Invoke only from the user's login-item toggle.
    func setEnabled(_ enabled: Bool) async {
        guard supportsAutomaticRegistration, !changing else { return }
        guard #available(macOS 13.0, *) else { return }
        changing = true; error = nil
        defer { changing = false; refresh() }
        do {
            let service = SMAppService.mainApp
            if enabled {
                if service.status != .enabled { try service.register() }
            } else if service.status != .notRegistered {
                try await service.unregister()
            }
        } catch {
            self.error = "Nie udało się zmienić startu przy logowaniu: \(error.localizedDescription)"
        }
    }

    func openSettings() {
        guard canUseSystemServices else { return }
        if #available(macOS 13.0, *) {
            SMAppService.openSystemSettingsLoginItems()
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preferences.users?LoginItems") {
            if !NSWorkspace.shared.open(url) { error = "Nie udało się otworzyć ustawień logowania macOS." }
        }
    }
}
