import SwiftUI
import TempCheckCore

private let accent = Color.teal

struct Dashboard: View {
    @ObservedObject var monitor: Monitor
    @State private var tab = 0
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
                        .disabled(monitor.busy).help("Odśwież teraz").accessibilityLabel("Odśwież teraz")
                }.padding(26)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if monitor.paused { notice("Pomiar wstrzymany. Wyświetlane są ostatnie odczyty.", icon: "pause.circle", color: .secondary) }
                        if let issue = monitor.snapshot.issue { notice(issue, icon: "info.circle", color: .orange) }
                        if tab == 0 { overview }
                        else if tab == 1 { sensorList }
                        else { settings }
                    }.padding(26)
                }
                Divider()
                HStack {
                    Circle().fill(monitor.paused ? Color.secondary : accent).frame(width: 6, height: 6)
                    Text(monitor.busy ? "Odczytywanie…" : "Aktualizacja: \(monitor.snapshot.date.formatted(date: .omitted, time: .standard))")
                    Spacer()
                    Text("Co \(Int(monitor.interval)) s · dane na urządzeniu")
                }.font(.caption).foregroundColor(.secondary).padding(.horizontal, 26).padding(.vertical, 13)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(nsColor: .windowBackgroundColor))
        }.frame(minWidth: 930, minHeight: 680).accentColor(accent)
            .alert("Eksport", isPresented: Binding(get: { monitor.error != nil }, set: { if !$0 { monitor.error = nil } })) {
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
        VStack(alignment: .leading, spacing: 20) {
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
                        Text("Ostatnie 15 minut").font(.caption).foregroundColor(.secondary)
                    }
                    if monitor.snapshot.temperatures.isEmpty { empty("Brak temperatur", detail: "Czujniki niedostępne na tym Macu lub brak dostępu do SMC.") }
                    else {
                        Picker("Czujnik", selection: $monitor.selectedID) {
                            ForEach(monitor.snapshot.temperatures) { Text("\($0.name) · \($0.id)").tag($0.id) }
                        }.frame(maxWidth: 400)
                        TemperatureChart(samples: monitor.history.samples, sensorID: monitor.selectedID, unit: monitor.unit)
                            .frame(height: 120)
                        let values = monitor.history.values(sensorID: monitor.selectedID)
                        HStack(spacing: 32) {
                            stat("MIN", monitor.unit.format(values.min()))
                            stat("ŚREDNIA", monitor.unit.format(values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)))
                            stat("MAKS", monitor.unit.format(values.max()))
                            Spacer()
                            Text(monitor.unit.format(monitor.selected?.celsius)).font(.title2.monospacedDigit()).foregroundColor(accent)
                        }
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
                    Text("Ostatnie 15 minut jest przechowywane w pamięci do zamknięcia aplikacji. Eksport obejmuje temperatury w °C i obroty w RPM. Puste pole oznacza brak odczytu.")
                        .foregroundColor(.secondary)
                    Button("Eksportuj historię do CSV…") { monitor.exportCSV() }.disabled(monitor.history.samples.isEmpty)
                    Text("TempCheck działa lokalnie i nie wysyła pomiarów do sieci.").font(.caption).foregroundColor(.secondary)
                }
            }
            Text("TempCheck 0.1 · macOS 12+\nDostępność czujników zależy od modelu Maca i wersji systemu.")
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
    var body: some View {
        let points = samples.map { sample in (sample.date, sample.temperatures.first { $0.id == sensorID }?.celsius.map(unit.convert)) }
        let values = points.compactMap { $0.1 }
        let lower = floor(((values.min() ?? 30) - 5) / 10) * 10
        let upper = max(lower + 20, ceil(((values.max() ?? 70) + 5) / 10) * 10)
        HStack(spacing: 10) {
            VStack { Text(String(format: "%.0f", upper)); Spacer(); Text(String(format: "%.0f", (lower + upper) / 2)); Spacer(); Text(String(format: "%.0f", lower)) }
                .font(.caption2.monospacedDigit()).foregroundColor(.secondary).frame(width: 30)
            GeometryReader { geo in
                let end = points.last?.0 ?? Date()
                let start = max(points.first?.0 ?? end, end.addingTimeInterval(-900))
                let span = max(30, end.timeIntervalSince(start))
                ZStack {
                    Path { path in for y in [0.0, 0.5, 1.0] { path.move(to: CGPoint(x: 0, y: geo.size.height * y)); path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height * y)) } }
                        .stroke(Color.secondary.opacity(0.16), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    Path { path in
                        var lastDate: Date?
                        for (date, value) in points {
                            guard let value else { lastDate = nil; continue }
                            let point = CGPoint(x: date.timeIntervalSince(start) / span * geo.size.width,
                                                y: (1 - (value - lower) / (upper - lower)) * geo.size.height)
                            if let last = lastDate, date.timeIntervalSince(last) <= 20 { path.addLine(to: point) }
                            else { path.move(to: point); path.addLine(to: CGPoint(x: point.x + 0.1, y: point.y)) }
                            lastDate = date
                        }
                    }.stroke(accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    if values.count < 2 { Text("Zbieranie historii…").font(.caption).foregroundColor(.secondary) }
                }
            }
        }.accessibilityElement(children: .ignore).accessibilityLabel("Wykres temperatury. \(values.count) poprawnych pomiarów. Jednostka \(unit.rawValue).")
    }
}
