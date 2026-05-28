// Core/Utilities/PrecisionCoachOutcomeStore.swift
import Foundation

/// Local persistence for precision coach outcome events (Phase 2).
/// Supports later analysis of plan compliance × FTP delta without a third-party SDK.
nonisolated enum PrecisionCoachOutcomeStore {
    enum EventKind: String, Codable, Sendable {
        case planGenerated
        case planStarted
        case planDayCompleted
        case adaptiveLoadAdjusted
        case ftpApplied
        case planForwardSimulated
        case workoutGenerated
    }

    struct Event: Codable, Sendable, Identifiable, Equatable {
        let id: UUID
        let kind: EventKind
        let timestamp: Date
        let planID: String?
        let dayID: String?
        let source: String?
        let numericValue: Double?
        let numericValue2: Double?
        let note: String?

        init(
            id: UUID = UUID(),
            kind: EventKind,
            timestamp: Date = .now,
            planID: String? = nil,
            dayID: String? = nil,
            source: String? = nil,
            numericValue: Double? = nil,
            numericValue2: Double? = nil,
            note: String? = nil
        ) {
            self.id = id
            self.kind = kind
            self.timestamp = timestamp
            self.planID = planID
            self.dayID = dayID
            self.source = source
            self.numericValue = numericValue
            self.numericValue2 = numericValue2
            self.note = note
        }
    }

    private static let storageKey = "precision_coach_outcome_events_v1"
    private static let maxEvents = 500

    nonisolated static func record(_ event: Event) {
        var events = load()
        events.append(event)
        if events.count > maxEvents {
            events = Array(events.suffix(maxEvents))
        }
        save(events)
    }

    nonisolated static func load(limit: Int? = nil) -> [Event] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [] }
        let decoded = (try? JSONDecoder().decode([Event].self, from: data)) ?? []
        guard let limit, limit < decoded.count else { return decoded }
        return Array(decoded.suffix(limit))
    }

    nonisolated static func events(forPlanID planID: String) -> [Event] {
        load().filter { $0.planID == planID }
    }

    nonisolated static func clearAll() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    private nonisolated static func save(_ events: [Event]) {
        guard let data = try? JSONEncoder().encode(events) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
