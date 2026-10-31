import Foundation

/// A sustained-temperature alert gate. A gap or missing reading never counts as heat exposure.
public struct ThermalAlertPolicy {
    public let thresholdCelsius: Double
    public let sustainedDuration: TimeInterval
    public let cooldown: TimeInterval
    public let hysteresis: Double
    public private(set) var snoozedUntil: Date?
    private var highSince: Date?
    private var lastSample: Date?
    private var lastAlert: Date?
    private var episodeAlerted = false

    public init(thresholdCelsius: Double = 90, sustainedDuration: TimeInterval = 60,
                cooldown: TimeInterval = 900, hysteresis: Double = 5) {
        self.thresholdCelsius = thresholdCelsius.isFinite ? min(150, max(1, thresholdCelsius)) : 90
        self.sustainedDuration = sustainedDuration.isFinite ? max(1, sustainedDuration) : 60
        self.cooldown = cooldown.isFinite ? max(0, cooldown) : 900
        self.hysteresis = hysteresis.isFinite ? max(0, hysteresis) : 5
    }

    /// Clears only consecutive-reading state; keeps the cooldown and episode latch.
    public mutating func resetContinuity() {
        highSince = nil
        lastSample = nil
    }

    public mutating func snooze(until date: Date) {
        snoozedUntil = date
        resetContinuity()
    }

    /// Call with enabled=false for a pause, sleep or demonstration sample.
    /// `continuityInterval` is the longest tolerated interval between real measurements.
    public mutating func evaluate(temp: Double?, at date: Date = Date(), enabled: Bool = true,
                                  continuityInterval: TimeInterval = 15) -> Bool {
        guard enabled, date.timeIntervalSince1970.isFinite,
              let temp = ReadingRules.temperature(temp) else {
            resetContinuity()
            return false
        }
        if let until = snoozedUntil {
            guard date >= until else { resetContinuity(); return false }
            snoozedUntil = nil
        }
        let maxGap = continuityInterval.isFinite ? max(0.1, continuityInterval) : 15
        if let previous = lastSample {
            let elapsed = date.timeIntervalSince(previous)
            if elapsed < 0 || elapsed > maxGap { highSince = nil }
        }
        lastSample = date
        if temp <= thresholdCelsius - hysteresis {
            episodeAlerted = false
        }
        guard temp >= thresholdCelsius else { highSince = nil; return false }
        guard !episodeAlerted else { return false }
        guard let since = highSince else { highSince = date; return false }
        guard date.timeIntervalSince(since) >= sustainedDuration else { return false }
        if let lastAlert, date.timeIntervalSince(lastAlert) < cooldown { return false }
        self.lastAlert = date
        episodeAlerted = true
        return true
    }
}
