import Foundation
import Observation

// MARK: - Ride Goal

/// A single quantified target the rider wants to hit during a free ride.
/// Multiple goals can be active at once; each fires a completion event independently.
struct RideGoal: Equatable {
    enum Kind: String, CaseIterable, Identifiable {
        case distance   // km
        case duration   // minutes
        case kilojoules // kJ
        case tss        // Training Stress Score

        var id: String { rawValue }

        var label: String {
            switch self {
            case .distance:   return "Distance"
            case .duration:   return "Duration"
            case .kilojoules: return "Energy"
            case .tss:        return "TSS"
            }
        }

        var unit: String {
            switch self {
            case .distance:   return "km"
            case .duration:   return "min"
            case .kilojoules: return "kJ"
            case .tss:        return "TSS"
            }
        }

        var icon: String {
            switch self {
            case .distance:   return "road.lanes"
            case .duration:   return "timer"
            case .kilojoules: return "flame.fill"
            case .tss:        return "chart.bar.fill"
            }
        }

        var defaultValue: Double {
            switch self {
            case .distance:   return 40
            case .duration:   return 60
            case .kilojoules: return 800
            case .tss:        return 80
            }
        }

        var step: Double {
            switch self {
            case .distance:   return 5
            case .duration:   return 5
            case .kilojoules: return 50
            case .tss:        return 10
            }
        }

        var range: ClosedRange<Double> {
            switch self {
            case .distance:   return 5...500
            case .duration:   return 5...600
            case .kilojoules: return 50...5000
            case .tss:        return 10...500
            }
        }
    }

    var kind: Kind
    var target: Double
    var isEnabled: Bool

    init(kind: Kind, target: Double? = nil, isEnabled: Bool = false) {
        self.kind = kind
        self.target = target ?? kind.defaultValue
        self.isEnabled = isEnabled
    }

    /// Current progress fraction (0–1) given live workout values.
    func progress(distance km: Double, elapsedMinutes: Double, kj: Double, tss: Double) -> Double {
        guard target > 0 else { return 0 }
        let current: Double
        switch kind {
        case .distance:   current = km
        case .duration:   current = elapsedMinutes
        case .kilojoules: current = kj
        case .tss:        current = tss
        }
        return min(1.0, current / target)
    }

    /// Returns true when the goal has just been crossed (current ≥ target, previous < target).
    func justCompleted(
        current km: Double, elapsedMinutes: Double, kj: Double, tss: Double,
        previous prevKm: Double, prevMinutes: Double, prevKj: Double, prevTss: Double
    ) -> Bool {
        let cur: Double
        let prev: Double
        switch kind {
        case .distance:   cur = km;             prev = prevKm
        case .duration:   cur = elapsedMinutes; prev = prevMinutes
        case .kilojoules: cur = kj;             prev = prevKj
        case .tss:        cur = tss;            prev = prevTss
        }
        return cur >= target && prev < target
    }
}

// MARK: - Quick Interval Config

/// Ad-hoc interval set for free rides — no training plan required.
struct QuickIntervalConfig: Equatable {
    var isEnabled: Bool    = false
    var sets: Int          = 4       // number of work intervals
    var workMinutes: Int   = 4       // work duration per interval (minutes)
    var restMinutes: Int   = 2       // recovery duration per interval (minutes)
    var targetZone: Int    = 4       // 1–5 power zone for the work intervals

    static let workRange:  ClosedRange<Int> = 1...30
    static let restRange:  ClosedRange<Int> = 1...20
    static let setsRange:  ClosedRange<Int> = 1...20
    static let zoneRange:  ClosedRange<Int> = 1...5

    var totalDurationMinutes: Int {
        sets * (workMinutes + restMinutes)
    }

    var summary: String {
        "\(sets) × \(workMinutes)' / \(restMinutes)' — \(totalDurationMinutes) min total"
    }
}

// MARK: - Unit System

enum UnitSystem: String, CaseIterable, Codable {
    case metric
    case imperial

    var label: String {
        switch self {
        case .metric: return "Metric (km, m)"
        case .imperial: return "Imperial (mi, ft)"
        }
    }
}

// MARK: - Indoor Power Display

/// How the large power readout (and matching zones) behave during an **indoor** ride or FTP test.
/// Stored samples, energy (kJ), and normalized power always use **per-second averages** of raw trainer data.
enum IndoorPowerHeroMode: String, CaseIterable, Codable {
    case oneSecond
    case threeSecond

    var label: String {
        switch self {
        case .oneSecond: return "1 second — responsive"
        case .threeSecond: return "3 second — smoother"
        }
    }
}

// MARK: - Indoor Speed Source

/// Where speed comes from during a free ride.
enum IndoorSpeedSource: String, CaseIterable, Codable {
    case sensor    // trainer-reported (FTMS characteristic)
    case computed  // physics model: power → speed

    var label: String {
        switch self {
        case .sensor: return "Trainer-reported"
        case .computed: return "Computed from power"
        }
    }
}

// MARK: - RidePreferences

/// Persisted ride-session preferences.
/// Values survive app restarts via UserDefaults and are observable so SwiftUI
/// views re-render automatically when any property changes.
@Observable
final class RidePreferences {

    // MARK: - Singleton

    static let shared = RidePreferences()

    // MARK: - Keys

    private enum Key {
        static let showLaps              = "ride_pref_show_laps"
        static let goals                 = "ride_pref_goals_v2"
        static let quickInterval         = "ride_pref_quick_interval_v1"
        static let lowCadenceWarning     = "ride_pref_low_cadence_warning"
        static let lowCadenceThreshold   = "ride_pref_low_cadence_threshold"
        static let stepAudioCue          = "ride_pref_step_audio_cue"
        static let navigationTurnCues    = "ride_pref_navigation_turn_cues"
        static let unitSystem            = "ride_pref_unit_system"
        static let outdoorAutoLapMeters  = "ride_pref_outdoor_auto_lap_meters"
        static let prioritizeNavMapless  = "ride_pref_prioritize_nav_mapless_v1"
        static let outdoorLiveActivity    = "ride_pref_outdoor_live_activity_v1"
        static let indoorLiveActivity     = "ride_pref_indoor_live_activity_v1"
        static let cscWheelCircumferenceM = "ride_pref_csc_wheel_circumference_m_v1"
        static let indoorPowerHeroMode = "ride_pref_indoor_power_hero_v1"
        static let riderWeightKg = "ride_pref_rider_weight_kg_v1"
        static let bikeWeightKg = "ride_pref_bike_weight_kg_v1"
        static let indoorSpeedSource = "ride_pref_indoor_speed_source_v1"
        static let riderCda = "ride_pref_rider_cda_v1"
    }

    // MARK: - Lap Visibility

    /// Whether the lap card is shown during an active ride.
    var showLaps: Bool {
        didSet { UserDefaults.standard.set(showLaps, forKey: Key.showLaps) }
    }

    // MARK: - Ride Goals

    /// The four possible goal types — always kept in this fixed order.
    var goals: [RideGoal] {
        didSet { persistGoals() }
    }

    /// Convenience: only goals that are toggled on.
    var activeGoals: [RideGoal] {
        goals.filter(\.isEnabled)
    }

    // MARK: - Quick Interval Config

    var quickInterval: QuickIntervalConfig {
        didSet { persistQuickInterval() }
    }

    // MARK: - Cadence Warning

    /// Whether to show a low-cadence nudge during a ride.
    var lowCadenceWarningEnabled: Bool {
        didSet { UserDefaults.standard.set(lowCadenceWarningEnabled, forKey: Key.lowCadenceWarning) }
    }

    /// RPM threshold below which a warning is shown (sustained for >30 s).
    var lowCadenceThreshold: Int {
        didSet { UserDefaults.standard.set(lowCadenceThreshold, forKey: Key.lowCadenceThreshold) }
    }

    // MARK: - Step Audio Cue

    /// Whether to play a chime + speech cue 10 s before a guided step ends.
    var stepAudioCueEnabled: Bool {
        didSet { UserDefaults.standard.set(stepAudioCueEnabled, forKey: Key.stepAudioCue) }
    }

    /// Spoken + haptic cues for outdoor turn-by-turn navigation.
    var navigationTurnCuesEnabled: Bool {
        didSet { UserDefaults.standard.set(navigationTurnCuesEnabled, forKey: Key.navigationTurnCues) }
    }

    // MARK: - Unit System

    /// Whether to display in metric (km, m) or imperial (mi, ft).
    var unitSystem: UnitSystem {
        didSet { UserDefaults.standard.set(unitSystem.rawValue, forKey: Key.unitSystem) }
    }

    /// Outdoor auto-lap interval in meters. `0` disables auto-lap.
    var outdoorAutoLapIntervalMeters: Double {
        didSet { UserDefaults.standard.set(outdoorAutoLapIntervalMeters, forKey: Key.outdoorAutoLapMeters) }
    }

    /// When the iPhone mapless bike-computer is shown, put navigation/route context directly under speed
    /// (recommended for turn-by-turn and GPX follow).
    var prioritizeNavigationInMaplessBikeComputer: Bool {
        didSet { UserDefaults.standard.set(prioritizeNavigationInMaplessBikeComputer, forKey: Key.prioritizeNavMapless) }
    }

    /// Lock Screen / Dynamic Island live activity while an outdoor ride is recording (requires Widget Extension target).
    var outdoorLiveActivityEnabled: Bool {
        didSet { UserDefaults.standard.set(outdoorLiveActivityEnabled, forKey: Key.outdoorLiveActivity) }
    }

    var indoorLiveActivityEnabled: Bool {
        didSet { UserDefaults.standard.set(indoorLiveActivityEnabled, forKey: Key.indoorLiveActivity) }
    }

    /// Wheel circumference in meters for Bluetooth **speed/cadence** speed derivation (CSC). Default ≈ 700×25 mm.
    var cscWheelCircumferenceMeters: Double {
        didSet { UserDefaults.standard.set(cscWheelCircumferenceMeters, forKey: Key.cscWheelCircumferenceM) }
    }

    /// Indoor / FTP hero power: last second’s mean vs a 3 s rolling mean of those seconds (recording unchanged).
    var indoorPowerHeroMode: IndoorPowerHeroMode {
        didSet { UserDefaults.standard.set(indoorPowerHeroMode.rawValue, forKey: Key.indoorPowerHeroMode) }
    }

    /// Rider body weight in kilograms. Used for physics-based speed computation.
    var riderWeightKg: Double {
        didSet { UserDefaults.standard.set(riderWeightKg, forKey: Key.riderWeightKg) }
    }

    /// Bike weight in kilograms. Used for physics-based speed computation.
    var bikeWeightKg: Double {
        didSet { UserDefaults.standard.set(bikeWeightKg, forKey: Key.bikeWeightKg) }
    }

    /// Where speed comes from during free rides: trainer-reported or computed from power.
    var indoorSpeedSource: IndoorSpeedSource {
        didSet { UserDefaults.standard.set(indoorSpeedSource.rawValue, forKey: Key.indoorSpeedSource) }
    }

    /// Aerodynamic drag area (CdA) in m². Used for physics-based speed computation.
    /// Typical values: 0.28 (drops) to 0.35 (upright).
    var riderCda: Double {
        didSet { UserDefaults.standard.set(riderCda, forKey: Key.riderCda) }
    }

    /// Sensible physical range for road tire circumference (meters).
    static let cscWheelCircumferenceRange: ClosedRange<Double> = 1.75...2.35

    /// Typical range for rider CdA (m²).
    static let cdaRange: ClosedRange<Double> = 0.23...0.40

    /// Sensible range for rider weight (kg).
    static let riderWeightRange: ClosedRange<Double> = 30...200

    /// Sensible range for bike weight (kg).
    static let bikeWeightRange: ClosedRange<Double> = 5...25

    var totalMassKg: Double { riderWeightKg + bikeWeightKg }

    var isImperial: Bool { unitSystem == .imperial }

    // MARK: - Init

    private init() {
        // showLaps — default true
        if UserDefaults.standard.object(forKey: Key.showLaps) != nil {
            self.showLaps = UserDefaults.standard.bool(forKey: Key.showLaps)
        } else {
            self.showLaps = true
        }

        // Goals — restore or build defaults
        if let data = UserDefaults.standard.data(forKey: Key.goals),
           let decoded = try? JSONDecoder().decode([GoalDTO].self, from: data) {
            self.goals = decoded.map { $0.toGoal() }
        } else {
            self.goals = RideGoal.Kind.allCases.map { RideGoal(kind: $0) }
        }

        // Quick interval
        if let data = UserDefaults.standard.data(forKey: Key.quickInterval),
           let decoded = try? JSONDecoder().decode(QuickIntervalDTO.self, from: data) {
            self.quickInterval = decoded.toConfig()
        } else {
            self.quickInterval = QuickIntervalConfig()
        }

        // Cadence warning — default enabled at 60 rpm
        if UserDefaults.standard.object(forKey: Key.lowCadenceWarning) != nil {
            self.lowCadenceWarningEnabled = UserDefaults.standard.bool(forKey: Key.lowCadenceWarning)
        } else {
            self.lowCadenceWarningEnabled = true
        }
        let storedThreshold = UserDefaults.standard.integer(forKey: Key.lowCadenceThreshold)
        self.lowCadenceThreshold = storedThreshold > 0 ? storedThreshold : 60

        // Step audio cue — default enabled
        if UserDefaults.standard.object(forKey: Key.stepAudioCue) != nil {
            self.stepAudioCueEnabled = UserDefaults.standard.bool(forKey: Key.stepAudioCue)
        } else {
            self.stepAudioCueEnabled = true
        }

        if UserDefaults.standard.object(forKey: Key.navigationTurnCues) != nil {
            self.navigationTurnCuesEnabled = UserDefaults.standard.bool(forKey: Key.navigationTurnCues)
        } else {
            self.navigationTurnCuesEnabled = true
        }

        // Unit system — default metric
        if let raw = UserDefaults.standard.string(forKey: Key.unitSystem),
           let system = UnitSystem(rawValue: raw) {
            self.unitSystem = system
        } else {
            self.unitSystem = .metric
        }

        // Outdoor auto-lap — default 1000 m; 0 = off
        let storedLap = UserDefaults.standard.double(forKey: Key.outdoorAutoLapMeters)
        if UserDefaults.standard.object(forKey: Key.outdoorAutoLapMeters) != nil {
            self.outdoorAutoLapIntervalMeters = max(0, min(50_000, storedLap))
        } else {
            self.outdoorAutoLapIntervalMeters = 1000
        }

        if UserDefaults.standard.object(forKey: Key.prioritizeNavMapless) != nil {
            self.prioritizeNavigationInMaplessBikeComputer = UserDefaults.standard.bool(forKey: Key.prioritizeNavMapless)
        } else {
            self.prioritizeNavigationInMaplessBikeComputer = true
        }

        if UserDefaults.standard.object(forKey: Key.outdoorLiveActivity) != nil {
            self.outdoorLiveActivityEnabled = UserDefaults.standard.bool(forKey: Key.outdoorLiveActivity)
        } else {
            self.outdoorLiveActivityEnabled = true
        }

        if UserDefaults.standard.object(forKey: Key.indoorLiveActivity) != nil {
            self.indoorLiveActivityEnabled = UserDefaults.standard.bool(forKey: Key.indoorLiveActivity)
        } else {
            self.indoorLiveActivityEnabled = true
        }

        let storedCirc = UserDefaults.standard.double(forKey: Key.cscWheelCircumferenceM)
        if UserDefaults.standard.object(forKey: Key.cscWheelCircumferenceM) != nil {
            self.cscWheelCircumferenceMeters = storedCirc.clamped(to: Self.cscWheelCircumferenceRange)
        } else {
            self.cscWheelCircumferenceMeters = 2.096
        }

        if let raw = UserDefaults.standard.string(forKey: Key.indoorPowerHeroMode),
           let mode = IndoorPowerHeroMode(rawValue: raw) {
            self.indoorPowerHeroMode = mode
        } else {
            self.indoorPowerHeroMode = .oneSecond
        }

        // Rider weight — default 75 kg
        let storedRiderWeight = UserDefaults.standard.double(forKey: Key.riderWeightKg)
        if UserDefaults.standard.object(forKey: Key.riderWeightKg) != nil {
            self.riderWeightKg = max(Self.riderWeightRange.lowerBound, min(Self.riderWeightRange.upperBound, storedRiderWeight))
        } else {
            self.riderWeightKg = 75
        }

        // Bike weight — default 8 kg (typical road bike)
        let storedBikeWeight = UserDefaults.standard.double(forKey: Key.bikeWeightKg)
        if UserDefaults.standard.object(forKey: Key.bikeWeightKg) != nil {
            self.bikeWeightKg = max(Self.bikeWeightRange.lowerBound, min(Self.bikeWeightRange.upperBound, storedBikeWeight))
        } else {
            self.bikeWeightKg = 8
        }

        // Indoor speed source — default sensor (trainer-reported)
        if let raw = UserDefaults.standard.string(forKey: Key.indoorSpeedSource),
           let source = IndoorSpeedSource(rawValue: raw) {
            self.indoorSpeedSource = source
        } else {
            self.indoorSpeedSource = .sensor
        }

        // Rider CdA — default 0.32 (hoods, relaxed position)
        let storedCda = UserDefaults.standard.double(forKey: Key.riderCda)
        if UserDefaults.standard.object(forKey: Key.riderCda) != nil {
            self.riderCda = max(Self.cdaRange.lowerBound, min(Self.cdaRange.upperBound, storedCda))
        } else {
            self.riderCda = PowerToSpeed.defaultCdA
        }
    }

    // MARK: - Persistence Helpers

    private func persistGoals() {
        let dtos = goals.map { GoalDTO(from: $0) }
        if let data = try? JSONEncoder().encode(dtos) {
            UserDefaults.standard.set(data, forKey: Key.goals)
        }
    }

    private func persistQuickInterval() {
        let dto = QuickIntervalDTO(from: quickInterval)
        if let data = try? JSONEncoder().encode(dto) {
            UserDefaults.standard.set(data, forKey: Key.quickInterval)
        }
    }

    // MARK: - Convenience Mutators

    /// Toggle a goal's enabled state by kind.
    func toggleGoal(_ kind: RideGoal.Kind) {
        guard let idx = goals.firstIndex(where: { $0.kind == kind }) else { return }
        goals[idx].isEnabled.toggle()
    }

    /// Update the target value for a goal kind.
    func setGoalTarget(_ kind: RideGoal.Kind, target: Double) {
        guard let idx = goals.firstIndex(where: { $0.kind == kind }) else { return }
        goals[idx].target = target.clamped(to: kind.range)
    }
}

// MARK: - Codable DTOs (keeps the public model clean)

private struct GoalDTO: Codable {
    var kind: String
    var target: Double
    var isEnabled: Bool

    init(from goal: RideGoal) {
        self.kind      = goal.kind.rawValue
        self.target    = goal.target
        self.isEnabled = goal.isEnabled
    }

    func toGoal() -> RideGoal {
        let k = RideGoal.Kind(rawValue: kind) ?? .distance
        return RideGoal(kind: k, target: target, isEnabled: isEnabled)
    }
}

private struct QuickIntervalDTO: Codable {
    var isEnabled: Bool
    var sets: Int
    var workMinutes: Int
    var restMinutes: Int
    var targetZone: Int

    init(from c: QuickIntervalConfig) {
        isEnabled   = c.isEnabled
        sets        = c.sets
        workMinutes = c.workMinutes
        restMinutes = c.restMinutes
        targetZone  = c.targetZone
    }

    func toConfig() -> QuickIntervalConfig {
        QuickIntervalConfig(
            isEnabled:   isEnabled,
            sets:        sets,
            workMinutes: workMinutes,
            restMinutes: restMinutes,
            targetZone:  targetZone
        )
    }
}

// MARK: - Comparable clamp helper

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
