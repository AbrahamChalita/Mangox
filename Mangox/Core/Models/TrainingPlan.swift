import Foundation
import SwiftData

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

// MARK: - Plan Progress (persisted via SwiftData)

@Model
final class TrainingPlanProgress {
    @Attribute(.unique) var planID: String
    var startDate: Date                          // when user started the plan
    var completedDayIDs: [String] = []           // IDs of completed PlanDays
    var skippedDayIDs: [String] = []
    var ftpAtStart: Int = 0
    var currentFTP: Int = 0
    var notes: [String: String] = [:]            // dayID → user note
    /// Optional display title for progress rows (Classicissima uses `CachedPlan` event name when empty).
    var aiPlanTitle: String = ""
    /// Scales guided ERG targets (1.0 = plan as written). Updated when plan-linked rides complete.
    var adaptiveLoadMultiplier: Double = 1.0

    init(planID: String, startDate: Date, ftp: Int, aiPlanTitle: String = "") {
        self.planID = planID
        self.startDate = startDate
        self.ftpAtStart = ftp
        self.currentFTP = ftp
        self.aiPlanTitle = aiPlanTitle
    }

    func isCompleted(_ dayID: String) -> Bool {
        completedDayIDs.contains(dayID)
    }

    func isSkipped(_ dayID: String) -> Bool {
        skippedDayIDs.contains(dayID)
    }

    func status(for dayID: String) -> PlanDayStatus {
        if completedDayIDs.contains(dayID) { return .completed }
        if skippedDayIDs.contains(dayID) { return .skipped }
        return .upcoming
    }

    func markCompleted(_ dayID: String) {
        if !completedDayIDs.contains(dayID) {
            completedDayIDs.append(dayID)
        }
        skippedDayIDs.removeAll { $0 == dayID }
    }

    func markSkipped(_ dayID: String) {
        if !skippedDayIDs.contains(dayID) {
            skippedDayIDs.append(dayID)
        }
        completedDayIDs.removeAll { $0 == dayID }
    }

    func unmark(_ dayID: String) {
        completedDayIDs.removeAll { $0 == dayID }
        skippedDayIDs.removeAll { $0 == dayID }
    }

    /// Returns the calendar date for a given plan day based on the plan start date.
    func calendarDate(for day: PlanDay) -> Date {
        let dayOffset = (day.weekNumber - 1) * 7 + (day.dayOfWeek - 1)
        return Calendar.current.date(byAdding: .day, value: dayOffset, to: startDate) ?? startDate
    }

    /// Completion stats
    var completedCount: Int { completedDayIDs.count }
    var skippedCount: Int { skippedDayIDs.count }
}

// MARK: - Wedding Weight Loss 2026 Plan Factory

enum WeddingWeightLossPlan {

    static func create() -> TrainingPlan {
        TrainingPlan(
            id: "wedding-weight-loss-2026",
            name: "Wedding Weight Loss & Base Building",
            eventName: "WEDDING DAY 2026",
            eventDate: "June 8, 2026",
            distance: "—",
            elevation: "—",
            location: "Indoor Training",
            description: "8-week evidence-based ENHANCED plan optimized for maximum fat loss. Includes Fasted Z2, Sprint Interval Training (SIT), Post-Ride Cold Exposure, Carb Cycling, Creatine & Hydration protocols, and progressive overload strength to ensure you look and feel your absolute best on your wedding day.",
            weeks: [
                week1(), week2(), week3(), week4(),
                week5(), week6(), week7(), week8()
            ]
        )
    }

    // MARK: - Phase 1: Foundation

    private static func week1() -> PlanWeek {
        PlanWeek(
            weekNumber: 1,
            phase: "Foundation",
            title: "Foundation Week 1",
            totalHoursLow: 4.5,
            totalHoursHigh: 5.5,
            tssTarget: 150...200,
            focus: "Easy base + intro intervals",
            days: [
                PlanDay(
                    id: "w1d1",
                    weekNumber: 1, dayOfWeek: 1,
                    dayType: .workout,
                    title: "Strength A",
                    durationMinutes: 25,
                    zone: .none,
                    notes: "Bodyweight strength: squats, lunges, planks, push-ups. 2-3 sets, 20-30 min total.",
                    intervals: [],
                    isKeyWorkout: false,
                    requiresFTPTest: false
                ),
                PlanDay(
                    id: "w1d2",
                    weekNumber: 1, dayOfWeek: 2,
                    dayType: .workout,
                    title: "Zone 2 Endurance",
                    durationMinutes: 50,
                    zone: .z2,
                    notes: "Simulation mode, 0-3% grade. 10 min warm-up → 30 min steady Z2 → 10 min cool-down. Cadence 85-95 rpm.",
                    intervals: [
                        IntervalSegment(order: 1, name: "Warm-Up", durationSeconds: 10 * 60, zone: .z1z2, notes: "Easy spin", suggestedTrainerMode: .simulation, simulationGrade: 0),
                        IntervalSegment(order: 2, name: "Zone 2 Steady", durationSeconds: 30 * 60, zone: .z2, notes: "Steady aerobic pace", suggestedTrainerMode: .simulation, simulationGrade: 2),
                        IntervalSegment(order: 3, name: "Cool Down", durationSeconds: 10 * 60, zone: .z1, notes: "Easy spin", suggestedTrainerMode: .simulation, simulationGrade: 0),
                    ],
                    isKeyWorkout: false,
                    requiresFTPTest: false
                ),
                PlanDay(
                    id: "w1d3",
                    weekNumber: 1, dayOfWeek: 3,
                    dayType: .rest,
                    title: "Rest or Easy 20min",
                    durationMinutes: 0,
                    zone: .rest,
                    notes: "Full rest or optional 20 min easy free ride if you feel good.",
                    intervals: [],
                    isKeyWorkout: false,
                    requiresFTPTest: false
                ),
                PlanDay(
                    id: "w1d4",
                    weekNumber: 1, dayOfWeek: 4,
                    dayType: .workout,
                    title: "Intro Intensity",
                    durationMinutes: 50,
                    zone: .z2z3,
                    notes: "ERG mode. 10 min warm-up → 4x(3 min moderate / 3 min easy) → cool-down.",
                    intervals: [
                        IntervalSegment(order: 1, name: "Warm-Up", durationSeconds: 10 * 60, zone: .z2, notes: "Easy spin", suggestedTrainerMode: .erg),
                        IntervalSegment(order: 2, name: "Moderate Effort", durationSeconds: 3 * 60, zone: .z3, repeats: 4, recoverySeconds: 3 * 60, recoveryZone: .z2, notes: "Moderate intervals", suggestedTrainerMode: .erg),
                        IntervalSegment(order: 3, name: "Cool Down", durationSeconds: 10 * 60, zone: .z1z2, notes: "Easy spin", suggestedTrainerMode: .erg),
                    ],
                    isKeyWorkout: true,
                    requiresFTPTest: false
                ),
                PlanDay(
                    id: "w1d5",
                    weekNumber: 1, dayOfWeek: 5,
                    dayType: .rest,
                    title: "Rest Day",
                    durationMinutes: 0,
                    zone: .rest,
                    notes: "Full recovery. Stay hydrated.",
                    intervals: [],
                    isKeyWorkout: false,
                    requiresFTPTest: false
                ),
                PlanDay(
                    id: "w1d6",
                    weekNumber: 1, dayOfWeek: 6,
                    dayType: .workout,
                    title: "Long Zone 2",
                    durationMinutes: 70,
                    zone: .z2,
                    notes: "Simulation mode, 2-4% rolling grade. Biggest fat-burn session of the week. Stay in Zone 2.",
                    intervals: [
                        IntervalSegment(order: 1, name: "Warm-Up", durationSeconds: 10 * 60, zone: .z1z2, notes: "Easy spin", suggestedTrainerMode: .simulation, simulationGrade: 2),
                        IntervalSegment(order: 2, name: "Zone 2 Long", durationSeconds: 50 * 60, zone: .z2, notes: "Steady aerobic pace", suggestedTrainerMode: .simulation, simulationGrade: 3),
                        IntervalSegment(order: 3, name: "Cool Down", durationSeconds: 10 * 60, zone: .z1, notes: "Easy spin", suggestedTrainerMode: .simulation, simulationGrade: 2),
                    ],
                    isKeyWorkout: true,
                    requiresFTPTest: false
                ),
                PlanDay(
                    id: "w1d7",
                    weekNumber: 1, dayOfWeek: 7,
                    dayType: .workout,
                    title: "Strength B",
                    durationMinutes: 25,
                    zone: .none,
                    notes: "Bodyweight strength session B. Optional 20 min easy spin after.",
                    intervals: [],
                    isKeyWorkout: false,
                    requiresFTPTest: false
                ),
            ]
        )
    }

    private static func week2() -> PlanWeek {
        PlanWeek(
            weekNumber: 2,
            phase: "Foundation",
            title: "Building Rhythm",
            totalHoursLow: 6,
            totalHoursHigh: 7,
            tssTarget: 250...300,
            focus: "Climbing intro",
            days: [
                PlanDay(
                    id: "w2d1",
                    weekNumber: 2, dayOfWeek: 1,
                    dayType: .workout,
                    title: "Active Recovery",
                    durationMinutes: 40,
                    zone: .z1,
                    notes: "Very easy spin, flush legs.",
                    intervals: [],
                    isKeyWorkout: false,
                    requiresFTPTest: false
                ),
                PlanDay(
                    id: "w2d2",
                    weekNumber: 2, dayOfWeek: 2,
                    dayType: .workout,
                    title: "Climbing Intervals",
                    durationMinutes: 60,
                    zone: .z3z4,
                    notes: "4x4 min at Z4 @ 60–70 RPM (seated), 3 min Z1 recovery. Simulate climbing.",
                    intervals: [
                        IntervalSegment(order: 1, name: "Warm-Up", durationSeconds: 10 * 60, zone: .z2, notes: "Easy spin to warm up", suggestedTrainerMode: .erg),
                        IntervalSegment(order: 2, name: "Climbing Interval", durationSeconds: 4 * 60, zone: .z4, repeats: 4, cadenceLow: 60, cadenceHigh: 70, recoverySeconds: 3 * 60, recoveryZone: .z1, notes: "Seated, hands on tops. Feel the climb.", suggestedTrainerMode: .simulation, simulationGrade: 5.0),
                        IntervalSegment(order: 3, name: "Cool Down", durationSeconds: 6 * 60, zone: .z1, notes: "Easy spin", suggestedTrainerMode: .erg),
                    ],
                    isKeyWorkout: true,
                    requiresFTPTest: false
                ),
                PlanDay(
                    id: "w2d3",
                    weekNumber: 2, dayOfWeek: 3,
                    dayType: .rest,
                    title: "Rest Day",
                    durationMinutes: 0,
                    zone: .rest,
                    notes: "Mobility work.",
                    intervals: [],
                    isKeyWorkout: false,
                    requiresFTPTest: false
                ),
                PlanDay(
                    id: "w2d4",
                    weekNumber: 2, dayOfWeek: 4,
                    dayType: .workout,
                    title: "Endurance + Tempo",
                    durationMinutes: 75,
                    zone: .z2z3,
                    notes: "60 min Z2, then 15 min steady Z3.",
                    intervals: [
                        IntervalSegment(order: 1, name: "Endurance", durationSeconds: 60 * 60, zone: .z2, notes: "Steady, conversational pace", suggestedTrainerMode: .erg),
                        IntervalSegment(order: 2, name: "Tempo Block", durationSeconds: 15 * 60, zone: .z3, notes: "Push to tempo for the finish", suggestedTrainerMode: .erg),
                    ],
                    isKeyWorkout: false,
                    requiresFTPTest: false
                ),
                PlanDay(
                    id: "w2d5",
                    weekNumber: 2, dayOfWeek: 5,
                    dayType: .workout,
                    title: "Sweet Spot",
                    durationMinutes: 60,
                    zone: .z3z4,
                    notes: "3x8 min at 88–93% FTP, 4 min Z1 recovery.",
                    intervals: [
                        IntervalSegment(order: 1, name: "Warm-Up", durationSeconds: 8 * 60, zone: .z2, notes: "Easy spin", suggestedTrainerMode: .erg),
                        IntervalSegment(order: 2, name: "Sweet Spot", durationSeconds: 8 * 60, zone: .z3z4, repeats: 3, recoverySeconds: 4 * 60, recoveryZone: .z1, notes: "88–93% FTP. Right below threshold.", suggestedTrainerMode: .erg),
                        IntervalSegment(order: 3, name: "Cool Down", durationSeconds: 4 * 60, zone: .z1, notes: "Easy spin", suggestedTrainerMode: .erg),
                    ],
                    isKeyWorkout: false,
                    requiresFTPTest: false
                ),
                PlanDay(
                    id: "w2d6",
                    weekNumber: 2, dayOfWeek: 6,
                    dayType: .workout,
                    title: "Long Ride",
                    durationMinutes: 105,
                    zone: .z2,
                    notes: "Include 2x10 min at Z3 in the middle of the ride.",
                    intervals: [
                        IntervalSegment(order: 1, name: "Endurance", durationSeconds: 30 * 60, zone: .z2, notes: "Build into the ride", suggestedTrainerMode: .erg),
                        IntervalSegment(order: 2, name: "Tempo Block", durationSeconds: 10 * 60, zone: .z3, repeats: 2, recoverySeconds: 5 * 60, recoveryZone: .z2, notes: "Tempo effort in the middle", suggestedTrainerMode: .simulation, simulationGrade: 3.0),
                        IntervalSegment(order: 3, name: "Endurance", durationSeconds: 30 * 60, zone: .z2, notes: "Steady to finish", suggestedTrainerMode: .erg),
                    ],
                    isKeyWorkout: true,
                    requiresFTPTest: false
                ),
                PlanDay(
                    id: "w2d7",
                    weekNumber: 2, dayOfWeek: 7,
                    dayType: .rest,
                    title: "Rest Day",
                    durationMinutes: 0,
                    zone: .rest,
                    notes: "Full recovery.",
                    intervals: [],
                    isKeyWorkout: false,
                    requiresFTPTest: false
                ),
            ]
        )
    }

    private static func week3() -> PlanWeek {
        PlanWeek(
            weekNumber: 3,
            phase: "Foundation",
            title: "Finding Legs",
            totalHoursLow: 7,
            totalHoursHigh: 8,
            tssTarget: 300...350,
            focus: "Volume + tempo",
            days: [
                PlanDay(
                    id: "w3d1",
                    weekNumber: 3, dayOfWeek: 1,
                    dayType: .workout,
                    title: "Active Recovery",
                    durationMinutes: 40,
                    zone: .z1,
                    notes: "Easy spin.",
                    intervals: [],
                    isKeyWorkout: false,
                    requiresFTPTest: false
                ),
                PlanDay(
                    id: "w3d2",
                    weekNumber: 3, dayOfWeek: 2,
                    dayType: .workout,
                    title: "Over-Under Intervals",
                    durationMinutes: 65,
                    zone: .z3z4,
                    notes: "4x(3 min Z4 + 2 min Z3), 3 min Z1 between sets.",
                    intervals: [
                        IntervalSegment(order: 1, name: "Warm-Up", durationSeconds: 10 * 60, zone: .z2, notes: "Easy spin", suggestedTrainerMode: .erg),
                        IntervalSegment(order: 2, name: "Over (Z4)", durationSeconds: 3 * 60, zone: .z4, repeats: 4, recoverySeconds: 0, notes: "Push above threshold", suggestedTrainerMode: .erg),
                        IntervalSegment(order: 3, name: "Under (Z3)", durationSeconds: 2 * 60, zone: .z3, repeats: 4, recoverySeconds: 3 * 60, recoveryZone: .z1, notes: "Drop to tempo, then full recovery between sets", suggestedTrainerMode: .erg),
                        IntervalSegment(order: 4, name: "Cool Down", durationSeconds: 7 * 60, zone: .z1, notes: "Easy spin", suggestedTrainerMode: .erg),
                    ],
                    isKeyWorkout: true,
                    requiresFTPTest: false
                ),
                PlanDay(
                    id: "w3d3",
                    weekNumber: 3, dayOfWeek: 3,
                    dayType: .rest,
                    title: "Rest Day",
                    durationMinutes: 0,
                    zone: .rest,
                    notes: "Stretch and rest.",
                    intervals: [],
                    isKeyWorkout: false,
                    requiresFTPTest: false
                ),
                PlanDay(
                    id: "w3d4",
                    weekNumber: 3, dayOfWeek: 4,
                    dayType: .workout,
                    title: "Endurance",
                    durationMinutes: 75,
                    zone: .z2,
                    notes: "Steady ride, practice fueling strategy.",
                    intervals: [],
                    isKeyWorkout: false,
                    requiresFTPTest: false
                ),
                PlanDay(
                    id: "w3d5",
                    weekNumber: 3, dayOfWeek: 5,
                    dayType: .workout,
                    title: "Climbing Repeats",
                    durationMinutes: 65,
                    zone: .z4,
                    notes: "5x4 min Z4 @ low cadence (60–65 RPM), 3 min Z1.",
                    intervals: [
                        IntervalSegment(order: 1, name: "Warm-Up", durationSeconds: 10 * 60, zone: .z2, notes: "Easy spin", suggestedTrainerMode: .erg),
                        IntervalSegment(order: 2, name: "Climbing Repeat", durationSeconds: 4 * 60, zone: .z4, repeats: 5, cadenceLow: 60, cadenceHigh: 65, recoverySeconds: 3 * 60, recoveryZone: .z1, notes: "Low cadence, high force. Seated climbing.", suggestedTrainerMode: .simulation, simulationGrade: 6.0),
                        IntervalSegment(order: 3, name: "Cool Down", durationSeconds: 5 * 60, zone: .z1, notes: "Easy spin", suggestedTrainerMode: .erg),
                    ],
                    isKeyWorkout: false,
                    requiresFTPTest: false
                ),
                PlanDay(
                    id: "w3d6",
                    weekNumber: 3, dayOfWeek: 6,
                    dayType: .workout,
                    title: "Long Ride",
                    durationMinutes: 120,
                    zone: .z2,
                    notes: "Include hill simulation: 3x8 min Z3.",
                    intervals: [
                        IntervalSegment(order: 1, name: "Endurance", durationSeconds: 30 * 60, zone: .z2, notes: "Easy start", suggestedTrainerMode: .erg),
                        IntervalSegment(order: 2, name: "Hill Simulation", durationSeconds: 8 * 60, zone: .z3, repeats: 3, recoverySeconds: 5 * 60, recoveryZone: .z2, notes: "Simulate race climbs", suggestedTrainerMode: .simulation, simulationGrade: 4.5),
                        IntervalSegment(order: 3, name: "Endurance", durationSeconds: 21 * 60, zone: .z2, notes: "Steady to finish", suggestedTrainerMode: .erg),
                    ],
                    isKeyWorkout: true,
                    requiresFTPTest: false
                ),
                PlanDay(
                    id: "w3d7",
                    weekNumber: 3, dayOfWeek: 7,
                    dayType: .rest,
                    title: "Rest Day",
                    durationMinutes: 0,
                    zone: .rest,
                    notes: "Recovery.",
                    intervals: [],
                    isKeyWorkout: false,
                    requiresFTPTest: false
                ),
            ]
        )
    }

    // MARK: - Phase 2: Build

    private static func week4() -> PlanWeek {
        PlanWeek(
            weekNumber: 4,
            phase: "Build",
            title: "Turning the Screws",
            totalHoursLow: 8,
            totalHoursHigh: 9,
            tssTarget: 350...400,
            focus: "Threshold work",
            days: [
                PlanDay(
                    id: "w4d1",
                    weekNumber: 4, dayOfWeek: 1,
                    dayType: .workout,
                    title: "Active Recovery",
                    durationMinutes: 45,
                    zone: .z1,
                    notes: "Easy legs.",
                    intervals: [],
                    isKeyWorkout: false,
                    requiresFTPTest: false
                ),
                PlanDay(
                    id: "w4d2",
                    weekNumber: 4, dayOfWeek: 2,
                    dayType: .workout,
                    title: "Threshold Intervals",
                    durationMinutes: 70,
                    zone: .z4,
                    notes: "3x10 min at FTP, 5 min Z1 recovery.",
                    intervals: [
                        IntervalSegment(order: 1, name: "Warm-Up", durationSeconds: 10 * 60, zone: .z2, notes: "Progressive warm-up", suggestedTrainerMode: .erg),
                        IntervalSegment(order: 2, name: "Threshold", durationSeconds: 10 * 60, zone: .z4, repeats: 3, recoverySeconds: 5 * 60, recoveryZone: .z1, notes: "Hold FTP. Even pacing is key.", suggestedTrainerMode: .erg),
                        IntervalSegment(order: 3, name: "Cool Down", durationSeconds: 5 * 60, zone: .z1, notes: "Easy spin", suggestedTrainerMode: .erg),
                    ],
                    isKeyWorkout: true,
                    requiresFTPTest: false
                ),
                PlanDay(
                    id: "w4d3",
                    weekNumber: 4, dayOfWeek: 3,
                    dayType: .rest,
                    title: "Rest Day",
                    durationMinutes: 0,
                    zone: .rest,
                    notes: "Recovery.",
                    intervals: [],
                    isKeyWorkout: false,
                    requiresFTPTest: false
                ),
                PlanDay(
                    id: "w4d4",
                    weekNumber: 4, dayOfWeek: 4,
                    dayType: .workout,
                    title: "Tempo Endurance",
                    durationMinutes: 80,
                    zone: .z2z3,
                    notes: "40 min Z2, 30 min Z3, 10 min Z2.",
                    intervals: [
                        IntervalSegment(order: 1, name: "Endurance", durationSeconds: 40 * 60, zone: .z2, notes: "Steady base", suggestedTrainerMode: .erg),
                        IntervalSegment(order: 2, name: "Tempo", durationSeconds: 30 * 60, zone: .z3, notes: "Sustained tempo effort", suggestedTrainerMode: .erg),
                        IntervalSegment(order: 3, name: "Cool Down", durationSeconds: 10 * 60, zone: .z2, notes: "Easy to finish", suggestedTrainerMode: .erg),
                    ],
                    isKeyWorkout: false,
                    requiresFTPTest: false
                ),
                PlanDay(
                    id: "w4d5",
                    weekNumber: 4, dayOfWeek: 5,
                    dayType: .workout,
                    title: "VO2max Intro",
                    durationMinutes: 60,
                    zone: .z5,
                    notes: "5x3 min at 110% FTP, 3 min Z1.",
                    intervals: [
                        IntervalSegment(order: 1, name: "Warm-Up", durationSeconds: 10 * 60, zone: .z2, notes: "Include a couple of 30s openers", suggestedTrainerMode: .erg),
                        IntervalSegment(order: 2, name: "VO2max", durationSeconds: 3 * 60, zone: .z5, repeats: 5, recoverySeconds: 3 * 60, recoveryZone: .z1, notes: "110% FTP. These should hurt. Breathe!", suggestedTrainerMode: .erg),
                        IntervalSegment(order: 3, name: "Cool Down", durationSeconds: 5 * 60, zone: .z1, notes: "Easy spin", suggestedTrainerMode: .erg),
                    ],
                    isKeyWorkout: true,
                    requiresFTPTest: false
                ),
                PlanDay(
                    id: "w4d6",
                    weekNumber: 4, dayOfWeek: 6,
                    dayType: .workout,
                    title: "Long Ride",
                    durationMinutes: 150,
                    zone: .z2z3,
                    notes: "Simulate race: include 4x10 min Z3 climbs.",
                    intervals: [
                        IntervalSegment(order: 1, name: "Endurance", durationSeconds: 25 * 60, zone: .z2, notes: "Easy start", suggestedTrainerMode: .erg),
                        IntervalSegment(order: 2, name: "Climb Simulation", durationSeconds: 10 * 60, zone: .z3, repeats: 4, recoverySeconds: 10 * 60, recoveryZone: .z2, notes: "Race-pace climbing", suggestedTrainerMode: .simulation, simulationGrade: 5.0),
                        IntervalSegment(order: 3, name: "Endurance", durationSeconds: 15 * 60, zone: .z2, notes: "Steady to finish", suggestedTrainerMode: .erg),
                    ],
                    isKeyWorkout: true,
                    requiresFTPTest: false
                ),
                PlanDay(
                    id: "w4d7",
                    weekNumber: 4, dayOfWeek: 7,
                    dayType: .rest,
                    title: "Rest Day",
                    durationMinutes: 0,
                    zone: .rest,
                    notes: "Full recovery.",
                    intervals: [],
                    isKeyWorkout: false,
                    requiresFTPTest: false
                ),
            ]
        )
    }

    private static func week5() -> PlanWeek {
        PlanWeek(
            weekNumber: 5,
            phase: "Enhanced Blueprint",
            title: "Peak Fat Oxidation",
            totalHoursLow: 5.5,
            totalHoursHigh: 6.5,
            tssTarget: 350...400,
            focus: "Fasted Z2 + SIT Max Burn",
            days: [
                PlanDay(
                    id: "w5d1",
                    weekNumber: 5, dayOfWeek: 1,
                    dayType: .workout,
                    title: "Strength A (Metabolism Boost)",
                    durationMinutes: 45,
                    zone: .none,
                    notes: "Progressive Overload: Compound movements (Squats, Deadlifts, Push-ups/Overhead Press, Rows). Use weights/heavy resistance bands. 5g Creatine.",
                    intervals: [],
                    isKeyWorkout: false,
                    requiresFTPTest: false
                ),
                PlanDay(
                    id: "w5d2",
                    weekNumber: 5, dayOfWeek: 2,
                    dayType: .workout,
                    title: "FASTED Zone 2",
                    durationMinutes: 80,
                    zone: .z2,
                    notes: "Water/Black Coffee only. 3-6mg/kg Caffeine 30 mins prior. Immediate 30g Protein Shake within 30 min post-ride.",
                    intervals: [
                        IntervalSegment(order: 1, name: "Warm-Up", durationSeconds: 10 * 60, zone: .z1z2, notes: "Easy spin to wake up legs", suggestedTrainerMode: .simulation, simulationGrade: 2),
                        IntervalSegment(order: 2, name: "Zone 2 Fasted", durationSeconds: 60 * 60, zone: .z2, notes: "Maximum fat oxidation. Do not spike HR above Z2.", suggestedTrainerMode: .simulation, simulationGrade: 3),
                        IntervalSegment(order: 3, name: "Cool Down", durationSeconds: 10 * 60, zone: .z1, notes: "Easy spin", suggestedTrainerMode: .simulation, simulationGrade: 1)
                    ],
                    isKeyWorkout: true,
                    requiresFTPTest: false
                ),
                PlanDay(
                    id: "w5d3",
                    weekNumber: 5, dayOfWeek: 3,
                    dayType: .rest,
                    title: "Active Recovery Walk",
                    durationMinutes: 30,
                    zone: .rest,
                    notes: "20-30 min brisk walk. Low Carb Day (<100g). Focus on healthy fats and high protein.",
                    intervals: [],
                    isKeyWorkout: false,
                    requiresFTPTest: false
                ),
                PlanDay(
                    id: "w5d4",
                    weekNumber: 5, dayOfWeek: 4,
                    dayType: .workout,
                    title: "The EPOC Maximizer (SIT)",
                    durationMinutes: 65,
                    zone: .z5,
                    notes: "Sprint Interval Training. Pre-load electrolytes before ride. 8x 20s ALL-OUT / 2m easy. 3 min Box Breathing immediately after.",
                    intervals: [
                        IntervalSegment(order: 1, name: "Warm-Up", durationSeconds: 15 * 60, zone: .z2, notes: "Include a few 5s spins to prep", suggestedTrainerMode: .erg),
                        IntervalSegment(order: 2, name: "Max Sprint (SIT)", durationSeconds: 20, zone: .z5, repeats: 8, recoverySeconds: 2 * 60, recoveryZone: .z1, notes: "ALL OUT. Maximum power generation.", suggestedTrainerMode: .erg),
                        IntervalSegment(order: 3, name: "Cool Down", durationSeconds: 15 * 60, zone: .z1, notes: "Spin out the legs + Box breathing", suggestedTrainerMode: .erg)
                    ],
                    isKeyWorkout: true,
                    requiresFTPTest: false
                ),
                PlanDay(
                    id: "w5d5",
                    weekNumber: 5, dayOfWeek: 5,
                    dayType: .rest,
                    title: "Active Recovery Prep",
                    durationMinutes: 30,
                    zone: .rest,
                    notes: "20-30 min walk + 15 mins mobility. Low Carb Day (<100g). Stop eating by 7 PM.",
                    intervals: [],
                    isKeyWorkout: false,
                    requiresFTPTest: false
                ),
                PlanDay(
                    id: "w5d6",
                    weekNumber: 5, dayOfWeek: 6,
                    dayType: .workout,
                    title: "Endurance & Anaerobic Finisher",
                    durationMinutes: 100,
                    zone: .z2,
                    notes: "Steady Z2 pacing. The Finisher: Last 10 min do 5x [30s HARD / 30s EASY]. 10-15 min cold shower post-ride.",
                    intervals: [
                        IntervalSegment(order: 1, name: "Endurance base", durationSeconds: 80 * 60, zone: .z2, notes: "Consistent Z2 base building", suggestedTrainerMode: .simulation, simulationGrade: 3.5),
                        IntervalSegment(order: 2, name: "Anaerobic Finisher", durationSeconds: 30, zone: .z5, repeats: 5, recoverySeconds: 30, recoveryZone: .z1, notes: "Spike EPOC calorie burn", suggestedTrainerMode: .erg),
                        IntervalSegment(order: 3, name: "Cool Down", durationSeconds: 10 * 60, zone: .z1, notes: "Easy spin, prep for cold shower", suggestedTrainerMode: .erg)
                    ],
                    isKeyWorkout: true,
                    requiresFTPTest: false
                ),
                PlanDay(
                    id: "w5d7",
                    weekNumber: 5, dayOfWeek: 7,
                    dayType: .workout,
                    title: "Strength B (Structural)",
                    durationMinutes: 35,
                    zone: .none,
                    notes: "Core, stability, lighter compound movements. High Carb Day (200-250g).",
                    intervals: [],
                    isKeyWorkout: false,
                    requiresFTPTest: false
                )
            ]
        )
    }

    private static func week6() -> PlanWeek {
        PlanWeek(
            weekNumber: 6,
            phase: "Enhanced Blueprint",
            title: "Peak Fat Oxidation 2",
            totalHoursLow: 5.5,
            totalHoursHigh: 6.5,
            tssTarget: 360...410,
            focus: "Fasted Z2 + SIT Max Burn",
            days: [
                PlanDay(
                    id: "w6d1",
                    weekNumber: 6, dayOfWeek: 1,
                    dayType: .workout,
                    title: "Strength A (Metabolism Boost)",
                    durationMinutes: 45,
                    zone: .none,
                    notes: "Progressive Overload: Add more weight. 5g Creatine.",
                    intervals: [],
                    isKeyWorkout: false,
                    requiresFTPTest: false
                ),
                PlanDay(
                    id: "w6d2",
                    weekNumber: 6, dayOfWeek: 2,
                    dayType: .workout,
                    title: "FASTED Zone 2",
                    durationMinutes: 80,
                    zone: .z2,
                    notes: "Water/Black Coffee only. 3-6mg/kg Caffeine 30 mins prior. Immediate 30g Protein Shake within 30 min post-ride.",
                    intervals: [
                        IntervalSegment(order: 1, name: "Warm-Up", durationSeconds: 10 * 60, zone: .z1z2, notes: "Easy spin", suggestedTrainerMode: .simulation, simulationGrade: 2),
                        IntervalSegment(order: 2, name: "Zone 2 Fasted", durationSeconds: 60 * 60, zone: .z2, notes: "Maximum fat oxidation. Focus on steady breathing.", suggestedTrainerMode: .simulation, simulationGrade: 3.5),
                        IntervalSegment(order: 3, name: "Cool Down", durationSeconds: 10 * 60, zone: .z1, notes: "Easy spin", suggestedTrainerMode: .simulation, simulationGrade: 1)
                    ],
                    isKeyWorkout: true,
                    requiresFTPTest: false
                ),
                PlanDay(
                    id: "w6d3",
                    weekNumber: 6, dayOfWeek: 3,
                    dayType: .rest,
                    title: "Active Recovery Walk",
                    durationMinutes: 30,
                    zone: .rest,
                    notes: "20-30 min brisk walk. Low Carb Day (<100g).",
                    intervals: [],
                    isKeyWorkout: false,
                    requiresFTPTest: false
                ),
                PlanDay(
                    id: "w6d4",
                    weekNumber: 6, dayOfWeek: 4,
                    dayType: .workout,
                    title: "The EPOC Maximizer (SIT)",
                    durationMinutes: 65,
                    zone: .z5,
                    notes: "Sprint Interval Training. Pre-load electrolytes. 9x 20s ALL-OUT / 2m easy. 3 min Box Breathing.",
                    intervals: [
                        IntervalSegment(order: 1, name: "Warm-Up", durationSeconds: 15 * 60, zone: .z2, notes: "Include a few 5s spins", suggestedTrainerMode: .erg),
                        IntervalSegment(order: 2, name: "Max Sprint (SIT)", durationSeconds: 20, zone: .z5, repeats: 9, recoverySeconds: 2 * 60, recoveryZone: .z1, notes: "ALL OUT.", suggestedTrainerMode: .erg),
                        IntervalSegment(order: 3, name: "Cool Down", durationSeconds: 15 * 60, zone: .z1, notes: "Spin out the legs + Box breathing", suggestedTrainerMode: .erg)
                    ],
                    isKeyWorkout: true,
                    requiresFTPTest: false
                ),
                PlanDay(
                    id: "w6d5",
                    weekNumber: 6, dayOfWeek: 5,
                    dayType: .rest,
                    title: "Active Recovery Prep",
                    durationMinutes: 30,
                    zone: .rest,
                    notes: "20-30 min walk + 15 mins mobility. Low Carb Day (<100g). Stop eating by 7 PM.",
                    intervals: [],
                    isKeyWorkout: false,
                    requiresFTPTest: false
                ),
                PlanDay(
                    id: "w6d6",
                    weekNumber: 6, dayOfWeek: 6,
                    dayType: .workout,
                    title: "Endurance & Anaerobic Finisher",
                    durationMinutes: 110,
                    zone: .z2,
                    notes: "Steady Z2 pacing. 10-15 min cold shower post-ride.",
                    intervals: [
                        IntervalSegment(order: 1, name: "Endurance base", durationSeconds: 90 * 60, zone: .z2, notes: "Consistent Z2 base building", suggestedTrainerMode: .simulation, simulationGrade: 4),
                        IntervalSegment(order: 2, name: "Anaerobic Finisher", durationSeconds: 30, zone: .z5, repeats: 5, recoverySeconds: 30, recoveryZone: .z1, notes: "Spike EPOC calorie burn", suggestedTrainerMode: .erg),
                        IntervalSegment(order: 3, name: "Cool Down", durationSeconds: 10 * 60, zone: .z1, notes: "Easy spin", suggestedTrainerMode: .erg)
                    ],
                    isKeyWorkout: true,
                    requiresFTPTest: false
                ),
                PlanDay(
                    id: "w6d7",
                    weekNumber: 6, dayOfWeek: 7,
                    dayType: .workout,
                    title: "Strength B (Structural)",
                    durationMinutes: 35,
                    zone: .none,
                    notes: "Core, stability, lighter compound movements. High Carb Day.",
                    intervals: [],
                    isKeyWorkout: false,
                    requiresFTPTest: false
                )
            ]
        )
    }

    private static func week7() -> PlanWeek {
        PlanWeek(
            weekNumber: 7,
            phase: "Enhanced Blueprint",
            title: "Peak Fat Oxidation 3",
            totalHoursLow: 5.5,
            totalHoursHigh: 6.5,
            tssTarget: 370...420,
            focus: "Fasted Z2 + SIT Max Burn",
            days: [
                PlanDay(
                    id: "w7d1",
                    weekNumber: 7, dayOfWeek: 1,
                    dayType: .workout,
                    title: "Strength A (Metabolism Boost)",
                    durationMinutes: 45,
                    zone: .none,
                    notes: "Progressive Overload: Add more weight. 5g Creatine.",
                    intervals: [],
                    isKeyWorkout: false,
                    requiresFTPTest: false
                ),
                PlanDay(
                    id: "w7d2",
                    weekNumber: 7, dayOfWeek: 2,
                    dayType: .workout,
                    title: "FASTED Zone 2",
                    durationMinutes: 80,
                    zone: .z2,
                    notes: "Water/Black Coffee only. 3-6mg/kg Caffeine 30 mins prior. Immediate 30g Protein Shake within 30 min post-ride.",
                    intervals: [
                        IntervalSegment(order: 1, name: "Warm-Up", durationSeconds: 10 * 60, zone: .z1z2, notes: "Easy spin", suggestedTrainerMode: .simulation, simulationGrade: 2),
                        IntervalSegment(order: 2, name: "Zone 2 Fasted", durationSeconds: 60 * 60, zone: .z2, notes: "Maximum fat oxidation. Focus on steady breathing.", suggestedTrainerMode: .simulation, simulationGrade: 4.0),
                        IntervalSegment(order: 3, name: "Cool Down", durationSeconds: 10 * 60, zone: .z1, notes: "Easy spin", suggestedTrainerMode: .simulation, simulationGrade: 1)
                    ],
                    isKeyWorkout: true,
                    requiresFTPTest: false
                ),
                PlanDay(
                    id: "w7d3",
                    weekNumber: 7, dayOfWeek: 3,
                    dayType: .rest,
                    title: "Active Recovery Walk",
                    durationMinutes: 30,
                    zone: .rest,
                    notes: "20-30 min brisk walk. Low Carb Day (<100g).",
                    intervals: [],
                    isKeyWorkout: false,
                    requiresFTPTest: false
                ),
                PlanDay(
                    id: "w7d4",
                    weekNumber: 7, dayOfWeek: 4,
                    dayType: .workout,
                    title: "The EPOC Maximizer (SIT)",
                    durationMinutes: 65,
                    zone: .z5,
                    notes: "Sprint Interval Training. Pre-load electrolytes. 10x 20s ALL-OUT / 2m easy. 3 min Box Breathing.",
                    intervals: [
                        IntervalSegment(order: 1, name: "Warm-Up", durationSeconds: 15 * 60, zone: .z2, notes: "Include a few 5s spins", suggestedTrainerMode: .erg),
                        IntervalSegment(order: 2, name: "Max Sprint (SIT)", durationSeconds: 20, zone: .z5, repeats: 10, recoverySeconds: 2 * 60, recoveryZone: .z1, notes: "ALL OUT.", suggestedTrainerMode: .erg),
                        IntervalSegment(order: 3, name: "Cool Down", durationSeconds: 15 * 60, zone: .z1, notes: "Spin out the legs + Box breathing", suggestedTrainerMode: .erg)
                    ],
                    isKeyWorkout: true,
                    requiresFTPTest: false
                ),
                PlanDay(
                    id: "w7d5",
                    weekNumber: 7, dayOfWeek: 5,
                    dayType: .rest,
                    title: "Active Recovery Prep",
                    durationMinutes: 30,
                    zone: .rest,
                    notes: "20-30 min walk + 15 mins mobility. Low Carb Day (<100g). Stop eating by 7 PM.",
                    intervals: [],
                    isKeyWorkout: false,
                    requiresFTPTest: false
                ),
                PlanDay(
                    id: "w7d6",
                    weekNumber: 7, dayOfWeek: 6,
                    dayType: .workout,
                    title: "Endurance & Anaerobic Finisher",
                    durationMinutes: 120,
                    zone: .z2,
                    notes: "Steady Z2 pacing. 10-15 min cold shower post-ride.",
                    intervals: [
                        IntervalSegment(order: 1, name: "Endurance base", durationSeconds: 100 * 60, zone: .z2, notes: "Consistent Z2 base building", suggestedTrainerMode: .simulation, simulationGrade: 4),
                        IntervalSegment(order: 2, name: "Anaerobic Finisher", durationSeconds: 30, zone: .z5, repeats: 5, recoverySeconds: 30, recoveryZone: .z1, notes: "Spike EPOC calorie burn", suggestedTrainerMode: .erg),
                        IntervalSegment(order: 3, name: "Cool Down", durationSeconds: 10 * 60, zone: .z1, notes: "Easy spin", suggestedTrainerMode: .erg)
                    ],
                    isKeyWorkout: true,
                    requiresFTPTest: false
                ),
                PlanDay(
                    id: "w7d7",
                    weekNumber: 7, dayOfWeek: 7,
                    dayType: .workout,
                    title: "Strength B (Structural)",
                    durationMinutes: 35,
                    zone: .none,
                    notes: "Core, stability, lighter compound movements. High Carb Day.",
                    intervals: [],
                    isKeyWorkout: false,
                    requiresFTPTest: false
                )
            ]
        )
    }

    private static func week8() -> PlanWeek {
        PlanWeek(
            weekNumber: 8,
            phase: "Wedding Week",
            title: "Taper & Glow",
            totalHoursLow: 3,
            totalHoursHigh: 4,
            tssTarget: 150...200,
            focus: "De-stress & Carb Load",
            days: [
                PlanDay(
                    id: "w8d1",
                    weekNumber: 8, dayOfWeek: 1,
                    dayType: .workout,
                    title: "Strength Maintenance",
                    durationMinutes: 30,
                    zone: .none,
                    notes: "Bodyweight only. Keep it light, no heavy fatigue.",
                    intervals: [],
                    isKeyWorkout: false,
                    requiresFTPTest: false
                ),
                PlanDay(
                    id: "w8d2",
                    weekNumber: 8, dayOfWeek: 2,
                    dayType: .workout,
                    title: "FASTED Zone 2 (Short)",
                    durationMinutes: 50,
                    zone: .z2,
                    notes: "Water/Coffee. Easy fat oxidation.",
                    intervals: [
                        IntervalSegment(order: 1, name: "Warm-Up", durationSeconds: 10 * 60, zone: .z1z2, notes: "Easy spin", suggestedTrainerMode: .simulation, simulationGrade: 2),
                        IntervalSegment(order: 2, name: "Zone 2 Fasted", durationSeconds: 30 * 60, zone: .z2, notes: "Steady breathing.", suggestedTrainerMode: .simulation, simulationGrade: 2.0),
                        IntervalSegment(order: 3, name: "Cool Down", durationSeconds: 10 * 60, zone: .z1, notes: "Easy spin", suggestedTrainerMode: .simulation, simulationGrade: 1)
                    ],
                    isKeyWorkout: false,
                    requiresFTPTest: false
                ),
                PlanDay(
                    id: "w8d3",
                    weekNumber: 8, dayOfWeek: 3,
                    dayType: .rest,
                    title: "Active Recovery Walk",
                    durationMinutes: 30,
                    zone: .rest,
                    notes: "20-30 min brisk walk. Final wedding prep.",
                    intervals: [],
                    isKeyWorkout: false,
                    requiresFTPTest: false
                ),
                PlanDay(
                    id: "w8d4",
                    weekNumber: 8, dayOfWeek: 4,
                    dayType: .workout,
                    title: "The EPOC Maximizer (Light)",
                    durationMinutes: 45,
                    zone: .z5,
                    notes: "Just 4 sprints to keep metabolism firing without fatigue.",
                    intervals: [
                        IntervalSegment(order: 1, name: "Warm-Up", durationSeconds: 15 * 60, zone: .z2, notes: "Include a few 5s spins", suggestedTrainerMode: .erg),
                        IntervalSegment(order: 2, name: "Max Sprint (SIT)", durationSeconds: 20, zone: .z5, repeats: 4, recoverySeconds: 2 * 60, recoveryZone: .z1, notes: "ALL OUT.", suggestedTrainerMode: .erg),
                        IntervalSegment(order: 3, name: "Cool Down", durationSeconds: 15 * 60, zone: .z1, notes: "Spin out the legs + Box breathing", suggestedTrainerMode: .erg)
                    ],
                    isKeyWorkout: false,
                    requiresFTPTest: false
                ),
                PlanDay(
                    id: "w8d5",
                    weekNumber: 8, dayOfWeek: 5,
                    dayType: .rest,
                    title: "Pre-Wedding Relaxation",
                    durationMinutes: 30,
                    zone: .rest,
                    notes: "Walk + 15 mins mobility. Hydrate!",
                    intervals: [],
                    isKeyWorkout: false,
                    requiresFTPTest: false
                ),
                PlanDay(
                    id: "w8d6",
                    weekNumber: 8, dayOfWeek: 6,
                    dayType: .race,
                    title: "💍 WEDDING DAY",
                    durationMinutes: 0,
                    zone: .all,
                    notes: "Enjoy your day! You've put in the work. Stay hydrated and be present in the moment.",
                    intervals: [],
                    isKeyWorkout: true,
                    requiresFTPTest: false
                ),
                PlanDay(
                    id: "w8d7",
                    weekNumber: 8, dayOfWeek: 7,
                    dayType: .event,
                    title: "Celebrate! 🍾",
                    durationMinutes: 0,
                    zone: .none,
                    notes: "Honeymoon & Celebration Phase begins.",
                    intervals: [],
                    isKeyWorkout: false,
                    requiresFTPTest: false
                )
            ]
        )
    }
}

// MARK: - Plan resolution (built-in template)

enum PlanLibrary {
    /// Resolves a `TrainingPlan` by ID. Checks the built-in Classicissima plan first,
    /// then AI-generated plans in SwiftData when a `ModelContext` is provided.
    static func resolvePlan(planID: String?, modelContext: ModelContext? = nil) -> TrainingPlan? {
        guard let planID else { return nil }
        if planID == CachedPlan.shared.id { return CachedPlan.shared }
        if let ctx = modelContext {
            let descriptor = FetchDescriptor<AIGeneratedPlan>(
                predicate: #Predicate { $0.id == planID }
            )
            if let aiPlan = try? ctx.fetch(descriptor).first {
                return aiPlan.plan
            }
        }
        return nil
    }

    static func resolveDay(planID: String?, dayID: String?, modelContext: ModelContext? = nil) -> PlanDay? {
        guard let dayID, let plan = resolvePlan(planID: planID, modelContext: modelContext) else { return nil }
        return plan.day(id: dayID)
    }

    /// Next incomplete workout or FTP test day, preferring the most recently started plan.
    /// Chooses by **mapped calendar date** so a missed day in week 1 does not block “next” once the user is in a later week.
    static func nextScheduledWorkout(
        allProgress: [TrainingPlanProgress],
        modelContext: ModelContext
    ) -> (planID: String, plan: TrainingPlan, day: PlanDay, progress: TrainingPlanProgress)? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let sorted = allProgress.sorted { $0.startDate > $1.startDate }
        for p in sorted {
            guard let plan = resolvePlan(planID: p.planID, modelContext: modelContext) else { continue }
            let candidates = plan.allDays.filter { d in
                !p.isCompleted(d.id) && !p.isSkipped(d.id)
                    && (d.dayType == .workout || d.dayType == .ftpTest)
            }
            let futureOrToday = candidates.filter {
                calendar.startOfDay(for: p.calendarDate(for: $0)) >= today
            }
            if let day = futureOrToday.min(by: { p.calendarDate(for: $0) < p.calendarDate(for: $1) }) {
                return (p.planID, plan, day, p)
            }
            if let day = candidates.min(by: { p.calendarDate(for: $0) < p.calendarDate(for: $1) }) {
                return (p.planID, plan, day, p)
            }
        }
        return nil
    }
}
