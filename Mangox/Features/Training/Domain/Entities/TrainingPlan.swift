// Features/Training/Domain/Entities/TrainingPlan.swift
import Foundation

// MARK: - Suggested Trainer Mode

/// Hints for the dashboard on which FTMS control mode best matches a given interval.
/// The dashboard can auto-apply these when running a guided plan session.
enum SuggestedTrainerMode: String, Codable, Sendable, Hashable {
    /// ERG mode — trainer locks to the zone's target wattage.
    case erg
    /// Simulation mode — trainer adjusts resistance based on a virtual grade.
    case simulation
    /// No specific suggestion — rider self-regulates (free ride / resistance).
    case freeRide

    /// Resilient decoding — LLMs may produce "free_ride", "ERG", "sim", etc.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if let exact = SuggestedTrainerMode(rawValue: raw) {
            self = exact
            return
        }
        switch raw.lowercased().trimmingCharacters(in: .whitespaces) {
        case "erg": self = .erg
        case "simulation", "sim": self = .simulation
        case "freeride", "free_ride", "free ride", "free": self = .freeRide
        default: self = .erg
        }
    }

    var label: String {
        switch self {
        case .erg: return "ERG"
        case .simulation: return "SIM"
        case .freeRide: return "Free"
        }
    }

    var icon: String {
        switch self {
        case .erg: return "lock.fill"
        case .simulation: return "mountain.2.fill"
        case .freeRide: return "figure.outdoor.cycle"
        }
    }
}

// MARK: - Training Zone Target

enum TrainingZoneTarget: String, Codable, Sendable {
    case z1 = "Z1"
    case z2 = "Z2"
    case z3 = "Z3"
    case z4 = "Z4"
    case z5 = "Z5"
    case z1z2 = "Z1-Z2"
    case z2z3 = "Z2-Z3"
    case z3z4 = "Z3-Z4"
    case z3z5 = "Z3-Z5"
    case z4z5 = "Z4-Z5"
    case mixed = "Mixed"
    case all = "ALL"
    case rest = "Rest"
    case none = "—"

    /// Resilient decoding — LLMs may produce variants like "None", "-", "z1", "zone1", etc.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if let exact = TrainingZoneTarget(rawValue: raw) {
            self = exact
            return
        }
        // Normalize common LLM variations
        switch raw.lowercased().trimmingCharacters(in: .whitespaces) {
        case "z1": self = .z1
        case "z2": self = .z2
        case "z3": self = .z3
        case "z4": self = .z4
        case "z5": self = .z5
        case "z1-z2", "z1z2": self = .z1z2
        case "z2-z3", "z2z3": self = .z2z3
        case "z3-z4", "z3z4": self = .z3z4
        case "z3-z5", "z3z5": self = .z3z5
        case "z4-z5", "z4z5": self = .z4z5
        case "mixed": self = .mixed
        case "all": self = .all
        case "rest": self = .rest
        case "none", "-", "—", "n/a", "": self = .none
        default: self = .none
        }
    }

    var label: String { rawValue }

    var sortOrder: Int {
        switch self {
        case .rest, .none: return 0
        case .z1: return 1
        case .z1z2: return 2
        case .z2: return 3
        case .z2z3: return 4
        case .z3: return 5
        case .z3z4: return 6
        case .z3z5: return 7
        case .z4: return 8
        case .z4z5: return 9
        case .z5: return 10
        case .mixed: return 5
        case .all: return 6
        }
    }
}

// MARK: - Workout Day Type

enum PlanDayType: String, Codable, Sendable {
    case workout
    case rest
    case race
    case event       // kit pickup, celebration, etc.
    case ftpTest
    /// Planned session is optional — not treated as a mandatory key workout for compliance nudges.
    case optionalWorkout
    /// Easy spin / transit — counts toward planned volume, lower intensity default.
    case commute

    /// Resilient decoding — LLMs may produce "ftp_test", "Workout", etc.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if let exact = PlanDayType(rawValue: raw) {
            self = exact
            return
        }
        switch raw.lowercased().trimmingCharacters(in: .whitespaces) {
        case "workout": self = .workout
        case "rest", "recovery": self = .rest
        case "race": self = .race
        case "event": self = .event
        case "ftptest", "ftp_test", "ftp test": self = .ftpTest
        case "optional", "optional_workout", "optionalworkout": self = .optionalWorkout
        case "commute", "commuter": self = .commute
        default: self = .workout
        }
    }
}

// MARK: - Plan Day Status

enum PlanDayStatus: String, Codable, Sendable {
    case upcoming
    case completed
    case skipped
    case inProgress
}

// MARK: - Interval Segment

/// Describes one segment of a structured workout (e.g. "4 min at Z4 @ 60-70 RPM")
struct IntervalSegment: Codable, Identifiable, Sendable, Hashable {
    var id: String { "\(order)-\(name)" }
    let order: Int
    let name: String
    let durationSeconds: Int
    let zone: TrainingZoneTarget
    let repeats: Int               // 1 = do once, 4 = repeat 4 times
    let cadenceLow: Int?
    let cadenceHigh: Int?
    let recoverySeconds: Int       // recovery between repeats
    let recoveryZone: TrainingZoneTarget
    let notes: String
    let suggestedTrainerMode: SuggestedTrainerMode
    let simulationGrade: Double?   // grade % when suggestedTrainerMode == .simulation

    init(
        order: Int,
        name: String,
        durationSeconds: Int,
        zone: TrainingZoneTarget,
        repeats: Int = 1,
        cadenceLow: Int? = nil,
        cadenceHigh: Int? = nil,
        recoverySeconds: Int = 0,
        recoveryZone: TrainingZoneTarget = .z1,
        notes: String = "",
        suggestedTrainerMode: SuggestedTrainerMode = .erg,
        simulationGrade: Double? = nil
    ) {
        self.order = order
        self.name = name
        self.durationSeconds = durationSeconds
        self.zone = zone
        self.repeats = repeats
        self.cadenceLow = cadenceLow
        self.cadenceHigh = cadenceHigh
        self.recoverySeconds = recoverySeconds
        self.recoveryZone = recoveryZone
        self.notes = notes
        self.suggestedTrainerMode = suggestedTrainerMode
        self.simulationGrade = simulationGrade
    }

    enum CodingKeys: String, CodingKey {
        case order, name, durationSeconds, zone, repeats, cadenceLow, cadenceHigh
        case recoverySeconds, recoveryZone, notes, suggestedTrainerMode, simulationGrade
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        order = try c.decodeIfPresent(Int.self, forKey: .order) ?? 1
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Interval"
        durationSeconds = try c.decodeIfPresent(Int.self, forKey: .durationSeconds) ?? 0
        zone = try c.decodeIfPresent(TrainingZoneTarget.self, forKey: .zone) ?? .z2
        repeats = try c.decodeIfPresent(Int.self, forKey: .repeats) ?? 1
        cadenceLow = try c.decodeIfPresent(Int.self, forKey: .cadenceLow)
        cadenceHigh = try c.decodeIfPresent(Int.self, forKey: .cadenceHigh)
        recoverySeconds = try c.decodeIfPresent(Int.self, forKey: .recoverySeconds) ?? 0
        recoveryZone = try c.decodeIfPresent(TrainingZoneTarget.self, forKey: .recoveryZone) ?? .z1
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        suggestedTrainerMode = try c.decodeIfPresent(SuggestedTrainerMode.self, forKey: .suggestedTrainerMode) ?? .erg
        simulationGrade = try c.decodeIfPresent(Double.self, forKey: .simulationGrade)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(order, forKey: .order)
        try c.encode(name, forKey: .name)
        try c.encode(durationSeconds, forKey: .durationSeconds)
        try c.encode(zone, forKey: .zone)
        try c.encode(repeats, forKey: .repeats)
        try c.encodeIfPresent(cadenceLow, forKey: .cadenceLow)
        try c.encodeIfPresent(cadenceHigh, forKey: .cadenceHigh)
        try c.encode(recoverySeconds, forKey: .recoverySeconds)
        try c.encode(recoveryZone, forKey: .recoveryZone)
        try c.encode(notes, forKey: .notes)
        try c.encode(suggestedTrainerMode, forKey: .suggestedTrainerMode)
        try c.encodeIfPresent(simulationGrade, forKey: .simulationGrade)
    }

    /// Total time including all repeats and recovery between them
    var totalSeconds: Int {
        let workTime = durationSeconds * repeats
        let restTime = recoverySeconds * max(0, repeats - 1)
        return workTime + restTime
    }

    /// Target watt range for this segment based on the zone and current FTP.
    var targetWattRange: ClosedRange<Int>? {
        let ftp = Double(PowerZone.ftp)
        guard ftp > 0 else { return nil }
        switch zone {
        case .z1:       return Int(ftp * 0.0)...Int(ftp * 0.55)
        case .z2:       return Int(ftp * 0.55)...Int(ftp * 0.75)
        case .z3:       return Int(ftp * 0.75)...Int(ftp * 0.87)
        case .z4:       return Int(ftp * 0.87)...Int(ftp * 1.05)
        case .z5:       return Int(ftp * 1.05)...Int(ftp * 1.50)
        case .z1z2:     return Int(ftp * 0.0)...Int(ftp * 0.75)
        case .z2z3:     return Int(ftp * 0.55)...Int(ftp * 0.87)
        case .z3z4:     return Int(ftp * 0.75)...Int(ftp * 1.05)
        case .z3z5:     return Int(ftp * 0.75)...Int(ftp * 1.50)
        case .z4z5:     return Int(ftp * 0.87)...Int(ftp * 1.50)
        case .mixed, .all: return Int(ftp * 0.55)...Int(ftp * 1.20)
        case .rest, .none: return nil
        }
    }

    /// Mid-point target watts for ERG mode.
    var ergTargetWatts: Int? {
        guard let range = targetWattRange else { return nil }
        return (range.lowerBound + range.upperBound) / 2
    }
}

// MARK: - Plan Day

/// A single day in the training plan
struct PlanDay: Codable, Identifiable, Sendable, Hashable {
    let id: String
    let weekNumber: Int
    let dayOfWeek: Int              // 1=Mon, 2=Tue, ..., 7=Sun
    let dayType: PlanDayType
    let title: String
    let durationMinutes: Int        // 0 for rest/event days
    let zone: TrainingZoneTarget
    let notes: String
    let intervals: [IntervalSegment]
    let isKeyWorkout: Bool          // highlight in UI
    let requiresFTPTest: Bool

    init(
        id: String,
        weekNumber: Int,
        dayOfWeek: Int,
        dayType: PlanDayType,
        title: String,
        durationMinutes: Int,
        zone: TrainingZoneTarget,
        notes: String,
        intervals: [IntervalSegment],
        isKeyWorkout: Bool,
        requiresFTPTest: Bool
    ) {
        self.id = id
        self.weekNumber = weekNumber
        self.dayOfWeek = dayOfWeek
        self.dayType = dayType
        self.title = title
        self.durationMinutes = durationMinutes
        self.zone = zone
        self.notes = notes
        self.intervals = intervals
        self.isKeyWorkout = isKeyWorkout
        self.requiresFTPTest = requiresFTPTest
    }

    var dayLabel: String {
        switch dayOfWeek {
        case 1: return "Mon"
        case 2: return "Tue"
        case 3: return "Wed"
        case 4: return "Thu"
        case 5: return "Fri"
        case 6: return "Sat"
        case 7: return "Sun"
        default: return "Day \(dayOfWeek)"
        }
    }

    var formattedDuration: String {
        guard durationMinutes > 0 else { return "—" }
        let h = durationMinutes / 60
        let m = durationMinutes % 60
        if h > 0 && m > 0 {
            return "\(h)h \(m)m"
        } else if h > 0 {
            return "\(h)h"
        } else {
            return "\(m) min"
        }
    }

    /// Whether this day has a structured interval workout (vs. just steady-state)
    var hasStructuredIntervals: Bool {
        !intervals.isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case id, weekNumber, dayOfWeek, dayType, title, durationMinutes, zone, notes, intervals
        case isKeyWorkout, requiresFTPTest
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        weekNumber = try c.decodeIfPresent(Int.self, forKey: .weekNumber) ?? 1
        dayOfWeek = try c.decodeIfPresent(Int.self, forKey: .dayOfWeek) ?? 1
        dayType = try c.decodeIfPresent(PlanDayType.self, forKey: .dayType) ?? .rest
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        durationMinutes = try c.decodeIfPresent(Int.self, forKey: .durationMinutes) ?? 0
        zone = try c.decodeIfPresent(TrainingZoneTarget.self, forKey: .zone) ?? .none
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        intervals = try c.decodeIfPresent([IntervalSegment].self, forKey: .intervals) ?? []
        isKeyWorkout = try c.decodeIfPresent(Bool.self, forKey: .isKeyWorkout) ?? false
        requiresFTPTest = try c.decodeIfPresent(Bool.self, forKey: .requiresFTPTest) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(weekNumber, forKey: .weekNumber)
        try c.encode(dayOfWeek, forKey: .dayOfWeek)
        try c.encode(dayType, forKey: .dayType)
        try c.encode(title, forKey: .title)
        try c.encode(durationMinutes, forKey: .durationMinutes)
        try c.encode(zone, forKey: .zone)
        try c.encode(notes, forKey: .notes)
        try c.encode(intervals, forKey: .intervals)
        try c.encode(isKeyWorkout, forKey: .isKeyWorkout)
        try c.encode(requiresFTPTest, forKey: .requiresFTPTest)
    }
}

// MARK: - Plan Week

struct PlanWeek: Codable, Identifiable, Sendable {
    var id: Int { weekNumber }
    let weekNumber: Int
    let phase: String               // "Foundation", "Build", "Taper", "Race"
    let title: String
    let totalHoursLow: Double
    let totalHoursHigh: Double
    let tssTarget: ClosedRange<Int>
    let focus: String
    let days: [PlanDay]

    var formattedHours: String {
        if totalHoursLow == totalHoursHigh {
            return "~\(Int(totalHoursLow))h"
        }
        return "\(Int(totalHoursLow))–\(Int(totalHoursHigh))h"
    }

    // Custom decoding to accept both `tssTarget: {lowerBound, upperBound}` (built-in plans)
    // and `tssTargetLower/tssTargetUpper` (AI-generated plans from backend).
    enum CodingKeys: String, CodingKey {
        case weekNumber, phase, title, totalHoursLow, totalHoursHigh, tssTarget, focus, days
        case tssTargetLower, tssTargetUpper
    }

    init(weekNumber: Int, phase: String, title: String, totalHoursLow: Double, totalHoursHigh: Double, tssTarget: ClosedRange<Int>, focus: String, days: [PlanDay]) {
        self.weekNumber = weekNumber
        self.phase = phase
        self.title = title
        self.totalHoursLow = totalHoursLow
        self.totalHoursHigh = totalHoursHigh
        self.tssTarget = tssTarget
        self.focus = focus
        self.days = days
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        weekNumber = try c.decodeIfPresent(Int.self, forKey: .weekNumber) ?? 1
        phase = try c.decodeIfPresent(String.self, forKey: .phase) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        totalHoursLow = try c.decodeIfPresent(Double.self, forKey: .totalHoursLow) ?? 0
        totalHoursHigh = try c.decodeIfPresent(Double.self, forKey: .totalHoursHigh) ?? 0
        focus = try c.decodeIfPresent(String.self, forKey: .focus) ?? ""
        days = try c.decodeIfPresent([PlanDay].self, forKey: .days) ?? []

        // Try standard ClosedRange encoding first (lowerBound/upperBound)
        if let range = try? c.decode(ClosedRange<Int>.self, forKey: .tssTarget) {
            tssTarget = range
        } else if let lower = try? c.decode(Int.self, forKey: .tssTargetLower),
                  let upper = try? c.decode(Int.self, forKey: .tssTargetUpper) {
            // AI-generated format: separate lower/upper fields
            tssTarget = lower...upper
        } else {
            // Fallback: no TSS target provided
            tssTarget = 0...0
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(weekNumber, forKey: .weekNumber)
        try c.encode(phase, forKey: .phase)
        try c.encode(title, forKey: .title)
        try c.encode(totalHoursLow, forKey: .totalHoursLow)
        try c.encode(totalHoursHigh, forKey: .totalHoursHigh)
        try c.encode(tssTarget, forKey: .tssTarget)
        try c.encode(focus, forKey: .focus)
        try c.encode(days, forKey: .days)
    }
}

// MARK: - Training Plan

struct TrainingPlan: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let eventName: String
    let eventDate: String              // display string
    let distance: String
    let elevation: String
    let location: String
    let description: String
    let weeks: [PlanWeek]

    enum CodingKeys: String, CodingKey {
        case id, name, eventName, eventDate, distance, elevation, location, description, weeks
    }

    init(
        id: String,
        name: String,
        eventName: String,
        eventDate: String,
        distance: String,
        elevation: String,
        location: String,
        description: String,
        weeks: [PlanWeek]
    ) {
        self.id = id
        self.name = name
        self.eventName = eventName
        self.eventDate = eventDate
        self.distance = distance
        self.elevation = elevation
        self.location = location
        self.description = description
        self.weeks = weeks
    }

    /// Explicit `nonisolated` Codable implementation so decoding works from `nonisolated` contexts (Swift 6; avoids main-actor–isolated synthesized `Decodable`).
    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Plan"
        eventName = try c.decodeIfPresent(String.self, forKey: .eventName) ?? ""
        eventDate = try c.decodeIfPresent(String.self, forKey: .eventDate) ?? ""
        distance = try c.decodeIfPresent(String.self, forKey: .distance) ?? ""
        elevation = try c.decodeIfPresent(String.self, forKey: .elevation) ?? ""
        location = try c.decodeIfPresent(String.self, forKey: .location) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        weeks = try c.decodeIfPresent([PlanWeek].self, forKey: .weeks) ?? []
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(eventName, forKey: .eventName)
        try c.encode(eventDate, forKey: .eventDate)
        try c.encode(distance, forKey: .distance)
        try c.encode(elevation, forKey: .elevation)
        try c.encode(location, forKey: .location)
        try c.encode(description, forKey: .description)
        try c.encode(weeks, forKey: .weeks)
    }

    var totalWeeks: Int { weeks.count }

    var allDays: [PlanDay] {
        weeks.flatMap(\.days)
    }

    func day(id: String) -> PlanDay? {
        allDays.first { $0.id == id }
    }

    /// Decode JSON stored in SwiftData (`AIGeneratedPlan.planJSON`). Explicitly `nonisolated` for Swift 6 when called from model accessors.
    nonisolated static func decodeFromStoredJSON(_ data: Data) -> TrainingPlan? {
        try? JSONDecoder().decode(TrainingPlan.self, from: data)
    }

    /// Returns a copy with `days` replaced for the given `weekNumber` (e.g. after `/api/regenerate-plan-week`).
    func replacingDays(forWeekNumber weekNumber: Int, days: [PlanDay]) -> TrainingPlan {
        let newWeeks = weeks.map { week in
            guard week.weekNumber == weekNumber else { return week }
            return PlanWeek(
                weekNumber: week.weekNumber,
                phase: week.phase,
                title: week.title,
                totalHoursLow: week.totalHoursLow,
                totalHoursHigh: week.totalHoursHigh,
                tssTarget: week.tssTarget,
                focus: week.focus,
                days: days
            )
        }
        return TrainingPlan(
            id: id,
            name: name,
            eventName: eventName,
            eventDate: eventDate,
            distance: distance,
            elevation: elevation,
            location: location,
            description: description,
            weeks: newWeeks
        )
    }
}

// NOTE: PlanLibrary has been moved to the Data layer
// (Training/Data/DataSources/PlanLibrary.swift) to preserve Domain purity —
// it depends on SwiftData ModelContext / FetchDescriptor.
