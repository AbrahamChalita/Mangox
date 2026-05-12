// Core/Networking/Supabase/Mappers/LoggedActivitySyncDomain.swift
import Foundation
import Supabase
import SwiftData

struct LoggedActivitySyncDomain: SupabaseSyncDomain {
    let name = "logged_activities"

    private static let cursorKey = "mangox.sync.logged_activities.cursor"

    @MainActor
    func push(userId: UUID, client: SupabaseClient, context: ModelContext) async throws {
        let cursor = UserDefaults.standard.object(forKey: Self.cursorKey) as? Date ?? .distantPast

        let descriptor = FetchDescriptor<LoggedActivityRecord>(
            predicate: #Predicate { $0.updatedAt > cursor },
            sortBy: [SortDescriptor(\.updatedAt, order: .forward)]
        )
        let records = try context.fetch(descriptor)
        guard !records.isEmpty else { return }

        let rows = records.map { LoggedActivityUpsertRow(record: $0, userId: userId) }
        try await client
            .from("logged_activities")
            .upsert(rows, onConflict: "user_id,client_id")
            .execute()

        if let latest = records.map(\.updatedAt).max() {
            UserDefaults.standard.set(latest, forKey: Self.cursorKey)
        }
    }

    @MainActor
    func pull(userId: UUID, client: SupabaseClient, context: ModelContext) async throws {
        // Pull is a no-op in v1. Multi-device sync is the follow-up.
    }
}

// MARK: - Row encoding

private struct LoggedActivityUpsertRow: Codable, Sendable {
    let user_id: String
    let client_id: String
    let source: String
    let external_id: String?
    let activity_type: String
    let custom_label: String?
    let start_date: Date
    let duration_seconds: Int
    let intensity: String?
    let rpe: Int?
    let notes: String
    let distance_meters: Double?
    let elevation_gain_meters: Double?
    let avg_heart_rate: Int?
    let max_heart_rate: Int?
    let calories: Int?
    let sets: Int?
    let reps: Int?
    let weight_kg: Double?
    let strain: Double?
    let kilojoules: Double?
    let created_at: Date
    let updated_at: Date

    init(record: LoggedActivityRecord, userId: UUID) {
        self.user_id = userId.uuidString
        self.client_id = record.id.uuidString
        self.source = record.sourceRaw
        self.external_id = record.externalID
        self.activity_type = record.typeRaw
        self.custom_label = record.customLabel
        self.start_date = record.startDate
        self.duration_seconds = record.durationSeconds
        self.intensity = record.intensityRaw
        self.rpe = record.rpe > 0 ? record.rpe : nil
        self.notes = record.notes.isEmpty ? "" : record.notes
        self.distance_meters = record.distanceMeters >= 0 ? record.distanceMeters : nil
        self.elevation_gain_meters = record.elevationGainMeters >= 0 ? record.elevationGainMeters : nil
        self.avg_heart_rate = record.avgHeartRate > 0 ? record.avgHeartRate : nil
        self.max_heart_rate = record.maxHeartRate > 0 ? record.maxHeartRate : nil
        self.calories = record.calories > 0 ? record.calories : nil
        self.sets = record.sets > 0 ? record.sets : nil
        self.reps = record.reps > 0 ? record.reps : nil
        self.weight_kg = record.weightKg >= 0 ? record.weightKg : nil
        self.strain = record.strain >= 0 ? record.strain : nil
        self.kilojoules = record.kilojoules >= 0 ? record.kilojoules : nil
        self.created_at = record.createdAt
        self.updated_at = record.updatedAt
    }
}
