import SwiftUI
import TempCheckCore

private let accent = Color.teal

struct Dashboard: View {
    @ObservedObject var monitor: Monitor
    @State private var tab = 0
    init(monitor: Monitor, initialTab: Int = 0) {
        self.monitor = monitor; _tab = State(initialValue: initialTab)
    }
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 25) {
                HStack(spacing: 10) {
                    Image(systemName: "thermometer").font(.system(size: 25, weight: .medium)).foregroundColor(accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TempCheck").font(.headline)
                        Text("Twój Mac. Pod kontrolą.").font(.caption2).foregroundColor(.secondary)
                    }
                }.padding(.bottom, 12)
                nav("Przegląd", icon: "square.grid.2x2", value: 0)
                nav("Czujniki", icon: "waveform.path", value: 1)
                nav("Ustawienia", icon: "slider.horizontal.3", value: 2)
                Spacer()
                VStack(alignment: .leading, spacing: 6) {
                    Label(monitor.paused ? "Pomiar wstrzymany" : "Monitorowanie lokalne", systemImage: monitor.paused ? "pause.circle" : "checkmark.shield")
                        .font(.caption).foregroundColor(.secondary)
                    Text("macOS \(ProcessInfo.processInfo.operatingSystemVersionString.replacingOccurrences(of: "Version ", with: ""))")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }.padding(22).frame(width: 210).background(.ultraThinMaterial)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(["Temperatura i chłodzenie", "Wszystkie czujniki", "Ustawienia"][tab]).font(.system(size: 25, weight: .bold))
                        Text(monitor.demo ? "TRYB DEMONSTRACYJNY · dane przykładowe" : "Bieżące odczyty z Twojego Maca")
                            .font(.subheadline).foregroundColor(monitor.demo ? .orange : .secondary)
                    }
                    Spacer()
                    Button { monitor.paused.toggle() } label: { Image(systemName: monitor.paused ? "play.fill" : "pause.fill") }
                        .help(monitor.paused ? "Wznów monitorowanie" : "Wstrzymaj monitorowanie")
                        .accessibilityLabel(monitor.paused ? "Wznów monitorowanie" : "Wstrzymaj monitorowanie")
                    Button { monitor.refresh() } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(monitor.busy || monitor.historyLoading).help("Odśwież teraz").accessibilityLabel("Odśwież teraz")
                }.padding(26)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if monitor.paused { notice("Pomiar wstrzymany. Wyświetlane są ostatnie odczyty.", icon: "pause.circle", color: .secondary) }
                        if let issue = monitor.snapshot.issue { notice(issue, icon: "info.circle", color: .orange) }
                        if let issue = monitor.storageIssue { notice(issue, icon: "externaldrive.badge.exclamationmark", color: .orange) }
                        if tab == 0 { overview }
                        else if tab == 1 { sensorList }
                        else { settings }
                    }.padding(26)
                }
                Divider()
                HStack {
                    Circle().fill(monitor.paused ? Color.secondary : accent).frame(width: 6, height: 6)
                    Text(monitor.historyLoading ? "Wczytywanie historii…" : monitor.busy ? "Odczytywanie…" : "Aktualizacja: \(monitor.snapshot.date.formatted(date: .omitted, time: .standard))")
                    Spacer()
                    Text("Co \(Int(monitor.interval)) s · dane na urządzeniu")
                }.font(.caption).foregroundColor(.secondary).padding(.horizontal, 26).padding(.vertical, 13)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(nsColor: .windowBackgroundColor))
        }.frame(minWidth: 930, minHeight: 680).accentColor(accent)
            .alert("TempCheck", isPresented: Binding(get: { monitor.error != nil }, set: { if !$0 { monitor.error = nil } })) {
                Button("OK") { monitor.error = nil }
            } message: { Text(monitor.error ?? "") }
    }
    private func nav(_ title: String, icon: String, value: Int) -> some View {
        Button { tab = value } label: {
            Label(title, systemImage: icon).font(.system(size: 13, weight: tab == value ? .semibold : .regular))
                .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                .foregroundColor(tab == value ? accent : .primary)
                .background(tab == value ? accent.opacity(0.12) : .clear).cornerRadius(8)
        }.buttonStyle(.plain)
    }
    private var overview: some View {
        let samples = monitor.visibleHistory
        let end = Date()
        let gap = max(monitor.historyRange.bucketDuration * 2.5, monitor.interval * 2.5)
        return VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                metric("Najcieplejszy czujnik", value: monitor.unit.format(monitor.snapshot.hottest?.celsius),
                       detail: monitor.snapshot.hottest?.id ?? "Brak odczytu", icon: "thermometer", color: accent)
                metric("Stan cieplny macOS", value: monitor.snapshot.thermal.rawValue,
                       detail: "Ocena systemu", icon: "waveform.path.ecg", color: thermalColor)
            }
            card {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("Historia temperatury").font(.headline)
                        Spacer()
                        Picker("Zakres", selection: $monitor.historyRange) {
                            ForEach(HistoryRange.allCases) { Text($0.label).tag($0) }
                        }.pickerStyle(.segmented).labelsHidden().accessibilityLabel("Zakres historii").frame(width: 285)
                    }
                    if monitor.availableTemperatureSensors.isEmpty { empty("Brak temperatur", detail: "Czujniki niedostępne na tym Macu lub brak dostępu do SMC.") }
                    else {
                        Picker("Czujnik", selection: $monitor.selectedID) {
                            ForEach(monitor.availableTemperatureSensors) { Text("\($0.name) · \($0.id)").tag($0.id) }
                        }.frame(maxWidth: 400)
                        TemperatureChart(samples: samples, sensorID: monitor.selectedID, unit: monitor.unit,
                                         range: monitor.historyRange, end: end, maximumGap: gap)
                            .frame(height: 120)
                        let values = monitor.selectedHistoryValues
                        HStack(spacing: 32) {
                            stat("MIN", monitor.unit.format(values.min()))
                            stat("ŚREDNIA", monitor.unit.format(values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)))
                            stat("MAKS", monitor.unit.format(values.max()))
                            Spacer()
                            Text(monitor.unit.format(monitor.selected?.celsius)).font(.title2.monospacedDigit()).foregroundColor(accent)
                        }
                    }
                    HStack {
                        Text(monitor.historyRange == .fifteenMinutes ? "Bieżące pomiary" : "Średnie co \(Int(monitor.historyRange.bucketDuration / 60)) min")
                        Spacer()
                        Text("Historia zachowana po zamknięciu aplikacji")
                    }.font(.caption2).foregroundColor(.secondary)
                }
            }
            card {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Obciążenie CPU i GPU").font(.headline)
                        Spacer()
                        Label(loadText(monitor.snapshot.cpuUsagePercent), systemImage: "cpu").foregroundColor(.blue)
                        Label(loadText(monitor.snapshot.gpuUsagePercent), systemImage: "square.3.layers.3d").foregroundColor(.purple)
                    }
                    LoadChart(samples: samples, range: monitor.historyRange, end: end, maximumGap: gap).frame(height: 90)
                    Text("CPU — niebieski · GPU — fioletowy · Ten sam okres co wykres temperatury")
                        .font(.caption2).foregroundColor(.secondary)
                    if monitor.snapshot.gpuUsagePercent == nil {
                        Text("Obciążenie GPU jest niedostępne, jeśli sterownik nie udostępnia tego odczytu.").font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            fanSection
        }
    }
    private var thermalColor: Color {
        switch monitor.snapshot.thermal { case .nominal: return .teal; case .fair: return .yellow; case .serious: return .orange; case .critical: return .red; case .unknown: return .secondary }
    }
    private var fanSection: some View {
        card {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label("Wentylatory", systemImage: "fanblades").font(.headline)
                    Spacer()
                    Text("Sterowane przez macOS").font(.caption).foregroundColor(.secondary)
                }
                if monitor.snapshot.reportedFanCount == 0 {
                    empty("SMC zgłasza brak wentylatorów", detail: "Komputer może korzystać z chłodzenia pasywnego.")
                } else if monitor.snapshot.fans.isEmpty {
                    empty("Brak danych o wentylatorach", detail: "Nie udało się odczytać liczby wentylatorów.")
                } else {
                    ForEach(monitor.snapshot.fans) { fan in
                        HStack(spacing: 16) {
                            Image(systemName: "fanblades").font(.system(size: 28)).foregroundColor(accent).frame(width: 40)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Wentylator \(fan.id + 1)").font(.subheadline.weight(.medium))
                                Text(fan.rpm == nil ? "Odczyt niedostępny" : fan.rpm == 0 ? "Zatrzymany" : "Pracuje")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            if let rpm = fan.rpm { Text("\(Int(rpm.rounded()))").font(.title2.monospacedDigit()); Text("RPM").foregroundColor(.secondary) }
                            else { Text("— RPM").font(.title2).foregroundColor(.secondary) }
                        }
                        if let max = fan.maximum, max > 0, let rpm = fan.rpm {
                            ProgressView(value: min(rpm / max, 1)).tint(accent).accessibilityLabel("Prędkość względem maksimum wentylatora \(fan.id + 1)")
                        }
                    }
                }
            }
        }
    }
    private var sensorList: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(SensorGroup.allCases, id: \.self) { group in
                let sensors = monitor.snapshot.temperatures.filter { $0.group == group }
                if !sensors.isEmpty {
                    card {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(group.rawValue).font(.headline)
                            ForEach(sensors) { sensor in
                                HStack {
                                    Image(systemName: "thermometer").foregroundColor(accent)
                                    Text(sensor.name)
                                    Text(sensor.id).font(.caption.monospaced()).foregroundColor(.secondary)
                                    Spacer()
                                    Text(monitor.unit.format(sensor.celsius)).font(.body.monospacedDigit())
                                }
                            }
                        }
                    }
                }
            }
            if monitor.snapshot.temperatures.isEmpty { empty("Brak czujników", detail: "Lista pojawi się po poprawnym odczycie sprzętu.") }
            fanSection
            Text("Nazwy nierozpoznanych czujników zawierają klucz sprzętowy. Ich położenie zależy od modelu Maca.")
                .font(.caption).foregroundColor(.secondary)
        }
    }
    private var settings: some View {
        VStack(alignment: .leading, spacing: 20) {
            card {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Uruchamianie").font(.headline)
                    Toggle("Uruchamiaj TempCheck przy logowaniu", isOn: Binding(
                        get: { monitor.loginItem.isEnabled },
                        set: { enabled in Task { await monitor.loginItem.setEnabled(enabled) } }))
                        .disabled(!monitor.loginItem.supportsAutomaticRegistration || monitor.loginItem.changing)
                    Text(monitor.loginItem.statusText).font(.caption).foregroundColor(.secondary)
                    if let message = monitor.loginItem.error { Text(message).font(.caption).foregroundColor(.red) }
                    Button("Ustawienia logowania macOS…") { monitor.loginItem.openSettings() }.disabled(monitor.demo)
                }
            }
            card {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Pasek menu").font(.headline)
                    Picker("Wyświetlany odczyt", selection: $monitor.menuMetric) {
                        ForEach(MenuMetric.allCases, id: \.self) { Text($0.label).tag($0) }
                    }.frame(maxWidth: 420)
                    if monitor.menuMetric == .fan {
                        Picker("Wentylator", selection: $monitor.menuFanID) {
                            ForEach(monitor.snapshot.fans) { Text("Wentylator \($0.id + 1)").tag($0.id) }
                            if !monitor.snapshot.fans.contains(where: { $0.id == monitor.menuFanID }) {
                                Text("Wentylator \(monitor.menuFanID + 1) · brak odczytu").tag(monitor.menuFanID)
                            }
                        }.frame(maxWidth: 420)
                    }
                    Text("Dla CPU, GPU i baterii wyświetlany jest najcieplejszy rozpoznany czujnik danej grupy.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            card {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Powiadomienia o temperaturze").font(.headline)
                    Toggle("Powiadamiaj o utrzymującej się wysokiej temperaturze", isOn: Binding(
                        get: { monitor.alertsEnabled }, set: { enabled in Task { await monitor.setAlertsEnabled(enabled) } }))
                        .disabled(monitor.demo || monitor.notifications.requesting)
                    Text(monitor.notifications.statusText).font(.caption).foregroundColor(.secondary)
                    HStack {
                        Text("Próg alertu")
                        Slider(value: $monitor.alertThreshold, in: 70...110, step: 5).frame(maxWidth: 240)
                            .accessibilityLabel("Próg temperatury powiadomienia")
                        Text(monitor.unit.format(monitor.alertThreshold)).monospacedDigit()
                    }
                    Text("Alert po 60 sekundach ponad progiem CPU lub GPU. Kolejny po ochłodzeniu i co najmniej 15 minutach.")
                        .font(.caption).foregroundColor(.secondary)
                    HStack {
                        if let until = monitor.alertSnoozedUntil, until > Date() {
                            Text("Wyciszone do \(until.formatted(date: .omitted, time: .shortened))").font(.caption)
                            Button("Wznów alerty") { monitor.resumeAlerts() }
                        } else { Button("Wycisz na godzinę") { monitor.snoozeAlerts() }.disabled(!monitor.alertsEnabled) }
                        Spacer()
                        Button("Ustawienia powiadomień…") { monitor.notifications.openSettings() }.disabled(monitor.demo)
                    }
                    if let message = monitor.notifications.error { Text(message).font(.caption).foregroundColor(.red) }
                }
            }
            card {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Pomiary").font(.headline)
                    Picker("Jednostka temperatury", selection: $monitor.unit) {
                        ForEach(TemperatureUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).frame(maxWidth: 320)
                    Picker("Odświeżanie", selection: $monitor.interval) {
                        ForEach([1.0, 2, 5, 10], id: \.self) { Text("Co \(Int($0)) s").tag($0) }
                    }.frame(maxWidth: 320)
                    Text("Rzadsze pomiary ograniczają zużycie energii. Podczas uśpienia pomiary są wstrzymane.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            card {
                VStack(alignment: .leading, spacing: 15) {
                    Text("Historia i prywatność").font(.headline)
                    Text("Historia jest zapisywana lokalnie przez 7 dni i wraca po ponownym uruchomieniu. Starsze pomiary są uśredniane. Eksport obejmuje wybrany zakres, temperatury w °C, obroty w RPM i obciążenie CPU/GPU w %.")
                        .foregroundColor(.secondary)
                    Picker("Zakres historii", selection: $monitor.historyRange) {
                        ForEach(HistoryRange.allCases) { Text($0.label).tag($0) }
                    }.pickerStyle(.segmented)
                    Button("Eksportuj wybrany zakres do CSV…") { monitor.exportCSV() }.disabled(monitor.visibleHistory.isEmpty)
                    Text("TempCheck działa lokalnie i nie wysyła pomiarów do sieci.").font(.caption).foregroundColor(.secondary)
                }
            }
            Text("TempCheck 0.2 · macOS 12+\nDostępność czujników zależy od modelu Maca i wersji systemu.")
                .font(.caption).foregroundColor(.secondary)
        }
    }
    private func metric(_ title: String, value: String, detail: String, icon: String, color: Color) -> some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: icon).font(.caption).foregroundColor(.secondary)
                Text(value).font(.system(size: 28, weight: .semibold, design: .rounded)).foregroundColor(color).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                Text(detail).font(.caption).foregroundColor(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func loadText(_ value: Double?) -> String { value.map { "\(Int($0.rounded()))%" } ?? "— %" }
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content().padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor)).cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.06), lineWidth: 1))
    }
    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(title).font(.system(size: 9, weight: .semibold)).foregroundColor(.secondary); Text(value).font(.subheadline.monospacedDigit()) }
    }
    private func empty(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 7) { Text(title).font(.subheadline.weight(.medium)); Text(detail).font(.caption).foregroundColor(.secondary) }
            .padding(.vertical, 16)
    }
    private func notice(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon).font(.callout).foregroundColor(color).padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.08)).cornerRadius(10)
    }
}

struct TemperatureChart: View {
    let samples: [Snapshot]
    let sensorID: String
    let unit: TemperatureUnit
    let range: HistoryRange
    let end: Date
    let maximumGap: TimeInterval
    var body: some View {
        let points = samples.map { ($0.date, $0.temperatures.first { $0.id == sensorID }?.celsius.map(unit.convert)) }
        let values = points.compactMap { $0.1 }
        let lower = floor(((values.min() ?? 30) - 5) / 10) * 10
        let upper = max(lower + 20, ceil(((values.max() ?? 70) + 5) / 10) * 10)
        HistoryPlot(series: [PlotSeries(id: "temperature", points: points, color: accent)], lower: lower, upper: upper,
                    range: range, end: end, maximumGap: maximumGap)
            .accessibilityLabel("Wykres temperatury. \(values.count) poprawnych pomiarów. Jednostka \(unit.rawValue).")
    }
}

struct LoadChart: View {
    let samples: [Snapshot]
    let range: HistoryRange
    let end: Date
    let maximumGap: TimeInterval
    var body: some View {
        HistoryPlot(series: [
            PlotSeries(id: "CPU", points: samples.map { ($0.date, $0.cpuUsagePercent) }, color: .blue),
            PlotSeries(id: "GPU", points: samples.map { ($0.date, $0.gpuUsagePercent) }, color: .purple)
        ], lower: 0, upper: 100, range: range, end: end, maximumGap: maximumGap)
            .accessibilityLabel("Obciążenie CPU i GPU w procentach. Zakres \(range.label).")
    }
}

private struct PlotSeries: Identifiable {
    let id: String
    let points: [(Date, Double?)]
    let color: Color
}

private struct HistoryPlot: View {
    let series: [PlotSeries]
    let lower: Double
    let upper: Double
    let range: HistoryRange
    let end: Date
    let maximumGap: TimeInterval
    private var start: Date { end.addingTimeInterval(-range.duration) }
    private func label(_ date: Date) -> String {
        date.formatted(date: range == .day || range == .week ? .abbreviated : .omitted, time: .shortened)
    }
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                VStack {
                    Text(String(format: "%.0f", upper)); Spacer()
                    Text(String(format: "%.0f", (lower + upper) / 2)); Spacer()
                    Text(String(format: "%.0f", lower))
                }.font(.caption2.monospacedDigit()).foregroundColor(.secondary).frame(width: 30)
                GeometryReader { geo in
                    ZStack {
                        Path { path in
                            for y in [0.0, 0.5, 1.0] {
                                path.move(to: CGPoint(x: 0, y: geo.size.height * y))
                                path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height * y))
                            }
                        }.stroke(Color.secondary.opacity(0.16), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        ForEach(series) { line in
                            Path { path in
                                var last: Date?
                                for (date, value) in line.points {
                                    guard let value, date >= start, date <= end else { last = nil; continue }
                                    let point = CGPoint(x: date.timeIntervalSince(start) / range.duration * geo.size.width,
                                                        y: (1 - (value - lower) / (upper - lower)) * geo.size.height)
                                    if let previous = last, date.timeIntervalSince(previous) <= maximumGap { path.addLine(to: point) }
                                    else { path.move(to: point); path.addLine(to: CGPoint(x: point.x + 0.1, y: point.y)) }
                                    last = date
                                }
                            }.stroke(line.color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        }
                        if series.allSatisfy({ $0.points.compactMap { $0.1 }.count < 2 }) {
                            Text("Zbieranie historii…").font(.caption).foregroundColor(.secondary)
                        }
                    }.clipped()
                }
            }
            HStack { Text(label(start)); Spacer(); Text(label(end)) }
                .font(.system(size: 9)).foregroundColor(.secondary).padding(.leading, 40)
        }.accessibilityElement(children: .ignore)
    }
}
