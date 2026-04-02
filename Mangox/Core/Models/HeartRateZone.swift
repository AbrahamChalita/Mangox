import SwiftUI

/// Standard 5-zone heart rate model.
///
/// Supports two calculation methods:
/// - **Percentage of Max HR**: zone thresholds are simple percentages of max HR.
/// - **Karvonen (HR Reserve)**: zone thresholds are based on percentage of heart rate reserve
///   (max HR − resting HR) + resting HR, which is more accurate when resting HR is known.
struct HeartRateZone: Identifiable {

    // MARK: - Storage Keys

    private static let maxHRStorageKey = "user_max_hr"
    private static let restingHRStorageKey = "user_resting_hr"
    private static let manualMaxHRKey = "user_manual_max_hr_enabled"
    private static let manualRestingHRKey = "user_manual_resting_hr_enabled"
    private static let defaultMaxHR = 185
    private static let defaultRestingHR = 60

    let id: Int
    let name: String
    let pctLow: Double          // lower bound as fraction of max HR (or HRR)
    let pctHigh: Double         // upper bound as fraction of max HR (or HRR)
    let color: Color
    let bgColor: Color

    // MARK: - Persisted User Values

    /// The user's maximum heart rate in bpm.
    /// Can be set from HealthKit, manual entry, or a field test.
    static var maxHR: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: maxHRStorageKey)
            return value > 0 ? value : defaultMaxHR
        }
        set {
            UserDefaults.standard.set(max(100, newValue), forKey: maxHRStorageKey)
        }
    }

    /// The user's resting heart rate in bpm.
    /// When available, enables Karvonen (HR reserve) zone calculation.
    static var restingHR: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: restingHRStorageKey)
            return value > 0 ? value : defaultRestingHR
        }
        set {
            UserDefaults.standard.set(max(30, min(newValue, 120)), forKey: restingHRStorageKey)
        }
    }

    /// Whether a real resting HR value has been set (from HealthKit or manual entry).
    static var hasRestingHR: Bool {
        UserDefaults.standard.integer(forKey: restingHRStorageKey) > 0
    }

    /// Whether max HR is currently using a manual override from the app UI.
    static var hasManualMaxHROverride: Bool {
        UserDefaults.standard.bool(forKey: manualMaxHRKey)
    }

    /// Whether resting HR is currently using a manual override from the app UI.
    static var hasManualRestingHROverride: Bool {
        UserDefaults.standard.bool(forKey: manualRestingHRKey)
    }

    /// Set a manual max HR override.
    static func setManualMaxHR(_ bpm: Int) {
        maxHR = bpm
        UserDefaults.standard.set(true, forKey: manualMaxHRKey)
    }

    /// Clear manual max HR override and fall back to HealthKit/estimated values.
    static func clearManualMaxHROverride() {
        UserDefaults.standard.removeObject(forKey: manualMaxHRKey)
        UserDefaults.standard.removeObject(forKey: maxHRStorageKey)
    }

    /// Set a manual resting HR override.
    static func setManualRestingHR(_ bpm: Int) {
        restingHR = bpm
        UserDefaults.standard.set(true, forKey: manualRestingHRKey)
    }

    /// Clear manual resting HR override and fall back to HealthKit/default behavior.
    static func clearManualRestingHROverride() {
        UserDefaults.standard.removeObject(forKey: manualRestingHRKey)
        UserDefaults.standard.removeObject(forKey: restingHRStorageKey)
    }

    // MARK: - BPM Range

    /// The BPM range for this zone, computed using the Karvonen method when resting HR
    /// is available, otherwise falling back to simple % of max HR.
    var bpmRange: ClosedRange<Int> {
        if Self.hasRestingHR {
            return karvonenRange
        }
        return percentMaxRange
    }

    /// BPM range using simple percentage of max HR.
    var percentMaxRange: ClosedRange<Int> {
        let low = Int((pctLow * Double(Self.maxHR)).rounded())
        let high = Int((pctHigh * Double(Self.maxHR)).rounded())
        return low...high
    }

    /// BPM range using Karvonen (heart rate reserve) method.
    /// Target HR = ((max HR − resting HR) × intensity%) + resting HR
    var karvonenRange: ClosedRange<Int> {
        let reserve = Double(Self.maxHR - Self.restingHR)
        let resting = Double(Self.restingHR)
        let low = Int((pctLow * reserve + resting).rounded())
        let high = Int((pctHigh * reserve + resting).rounded())
        return low...high
    }

    // MARK: - Zone Definitions

    /// Standard 5-zone HR model (thresholds based on widely-used Coggan/Friel percentages).
    static let zones: [HeartRateZone] = [
        HeartRateZone(
            id: 1,
            name: "Recovery",
            pctLow: 0.00,
            pctHigh: 0.60,
            color: Color(red: 107/255, green: 127/255, blue: 212/255),
            bgColor: Color(red: 107/255, green: 127/255, blue: 212/255).opacity(0.12)
        ),
        HeartRateZone(
            id: 2,
            name: "Aerobic",
            pctLow: 0.60,
            pctHigh: 0.70,
            color: Color(red: 79/255, green: 195/255, blue: 161/255),
            bgColor: Color(red: 79/255, green: 195/255, blue: 161/255).opacity(0.12)
        ),
        HeartRateZone(
            id: 3,
            name: "Tempo",
            pctLow: 0.70,
            pctHigh: 0.80,
            color: Color(red: 240/255, green: 195/255, blue: 78/255),
            bgColor: Color(red: 240/255, green: 195/255, blue: 78/255).opacity(0.12)
        ),
        HeartRateZone(
            id: 4,
            name: "Threshold",
            pctLow: 0.80,
            pctHigh: 0.90,
            color: Color(red: 240/255, green: 122/255, blue: 58/255),
            bgColor: Color(red: 240/255, green: 122/255, blue: 58/255).opacity(0.12)
        ),
        HeartRateZone(
            id: 5,
            name: "VO2 Max",
            pctLow: 0.90,
            pctHigh: 1.00,
            color: Color(red: 232/255, green: 68/255, blue: 90/255),
            bgColor: Color(red: 232/255, green: 68/255, blue: 90/255).opacity(0.12)
        ),
    ]

    // MARK: - Zone Lookup

    /// Returns the heart rate zone for a given BPM value.
    static func zone(for bpm: Int) -> HeartRateZone {
        let maxHR = Double(Self.maxHR)
        guard maxHR > 0, bpm > 0 else { return zones.first! }

        if hasRestingHR {
            // Karvonen: intensity = (HR − resting) / (max − resting)
            let reserve = maxHR - Double(Self.restingHR)
            guard reserve > 0 else { return zones.first! }
            let intensity = (Double(bpm) - Double(Self.restingHR)) / reserve
            return zones.first { intensity >= $0.pctLow && intensity < $0.pctHigh }
                ?? zones.last!
        } else {
            // Simple % of max HR
            let pct = Double(bpm) / maxHR
            return zones.first { pct >= $0.pctLow && pct < $0.pctHigh }
                ?? zones.last!
        }
    }

    /// Percentage of max HR for a given BPM (simple method, always available).
    static func percentOfMax(bpm: Int) -> Double {
        guard maxHR > 0 else { return 0 }
        return Double(bpm) / Double(maxHR)
    }

    /// Percentage of heart rate reserve for a given BPM (Karvonen).
    /// Returns nil if resting HR is not set.
    static func percentOfReserve(bpm: Int) -> Double? {
        guard hasRestingHR else { return nil }
        let reserve = Double(maxHR - restingHR)
        guard reserve > 0 else { return nil }
        return (Double(bpm) - Double(restingHR)) / reserve
    }
}
