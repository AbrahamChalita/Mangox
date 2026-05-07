import Foundation
import Supabase
import SwiftData

// MARK: - AI generated plans

struct AIGeneratedPlanSyncDomain: SupabaseSyncDomain {
    let name = "ai_generated_plans"
    private static let cursorKey = "mangox.sync.ai_plans.cursor"

    @MainActor
    func push(userId: UUID, client: SupabaseClient, context: ModelContext) async throws {
        let cursor = UserDefaults.standard.object(forKey: Self.cursorKey) as? Date ?? .distantPast
        let descriptor = FetchDescriptor<AIGeneratedPlan>(
            predicate: #Predicate { $0.generatedAt > cursor },
            sortBy: [SortDescriptor(\.generatedAt, order: .forward)]
        )
        let plans = try context.fetch(descriptor)
        guard !plans.isEmpty else { return }

        var newCursor = cursor
        var rows: [Row] = []
        rows.reserveCapacity(plans.count)
        for plan in plans {
            rows.append(Row(plan: plan, userId: userId))
            if plan.generatedAt > newCursor { newCursor = plan.generatedAt }
        }
        try await client.from("ai_generated_plans").upsert(rows, onConflict: "id").execute()
        UserDefaults.standard.set(newCursor, forKey: Self.cursorKey)
    }

    private struct Row: Codable, Sendable {
        let id: String
        let user_id: String
        let title: String?
        let user_prompt: String
        let plan: AnyJSON
        let regeneration_inputs: AnyJSON?
        let generated_at: Date

        init(plan: AIGeneratedPlan, userId: UUID) {
            self.id = plan.id
            self.user_id = userId.uuidString
            self.title = nil
            self.user_prompt = plan.userPrompt
            self.plan = (try? JSONDecoder().decode(AnyJSON.self, from: plan.planJSON)) ?? .null
            if let data = plan.regenerationInputsJSON {
                self.regeneration_inputs = try? JSONDecoder().decode(AnyJSON.self, from: data)
            } else {
                self.regeneration_inputs = nil
            }
            self.generated_at = plan.generatedAt
        }
    }
}

// MARK: - Training plan progress

struct TrainingPlanProgressSyncDomain: SupabaseSyncDomain {
    let name = "training_plan_progress"

    @MainActor
    func push(userId: UUID, client: SupabaseClient, context: ModelContext) async throws {
        let progresses = try context.fetch(FetchDescriptor<TrainingPlanProgress>())
        guard !progresses.isEmpty else { return }

        let rows = progresses.compactMap { progress -> Row? in
            guard let planUUID = UUID(uuidString: progress.planID) else { return nil }
            return Row(progress: progress, planUUID: planUUID, userId: userId)
        }
        guard !rows.isEmpty else { return }

        try await client
            .from("training_plan_progress")
            .upsert(rows, onConflict: "user_id,plan_id")
            .execute()
    }

    private struct Row: Codable, Sendable {
        let user_id: String
        let plan_id: String
        let start_date: String          // YYYY-MM-DD
        let completed_day_ids: [String]
        let skipped_day_ids: [String]
        let ftp_at_start: Int
        let current_ftp: Int
        let ai_plan_title: String
        let adaptive_load_multiplier: Double
        let notes: AnyJSON

        init(progress: TrainingPlanProgress, planUUID: UUID, userId: UUID) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withYear, .withMonth, .withDay, .withDashSeparatorInDate]

            self.user_id = userId.uuidString
            self.plan_id = planUUID.uuidString
            self.start_date = formatter.string(from: progress.startDate)
            self.completed_day_ids = progress.completedDayIDs
            self.skipped_day_ids = progress.skippedDayIDs
            self.ftp_at_start = progress.ftpAtStart
            self.current_ftp = progress.currentFTP
            self.ai_plan_title = progress.aiPlanTitle
            self.adaptive_load_multiplier = progress.adaptiveLoadMultiplier
            self.notes = .object(progress.notes.mapValues { .string($0) })
        }
    }
}

// MARK: - Fitness settings snapshots (zone history)

struct ZoneSnapshotSyncDomain: SupabaseSyncDomain {
    let name = "zone_snapshots"
    private static let cursorKey = "mangox.sync.zone_snapshots.cursor"

    @MainActor
    func push(userId: UUID, client: SupabaseClient, context: ModelContext) async throws {
        let cursor = UserDefaults.standard.object(forKey: Self.cursorKey) as? Date ?? .distantPast
        let descriptor = FetchDescriptor<FitnessSettingsSnapshot>(
            predicate: #Predicate { $0.recordedAt > cursor },
            sortBy: [SortDescriptor(\.recordedAt, order: .forward)]
        )
        let snapshots = try context.fetch(descriptor)
        guard !snapshots.isEmpty else { return }

        var newCursor = cursor
        let rows = snapshots.map { snap -> Row in
            if snap.recordedAt > newCursor { newCursor = snap.recordedAt }
            return Row(snapshot: snap, userId: userId)
        }
        try await client.from("zone_snapshots").upsert(rows, onConflict: "id").execute()
        UserDefaults.standard.set(newCursor, forKey: Self.cursorKey)
    }

    private struct Row: Codable, Sendable {
        let id: String
        let user_id: String
        let recorded_at: Date
        let ftp_watts: Int?
        let max_hr: Int?
        let resting_hr: Int?
        let source: String

        init(snapshot: FitnessSettingsSnapshot, userId: UUID) {
            self.id = snapshot.id.uuidString
            self.user_id = userId.uuidString
            self.recorded_at = snapshot.recordedAt
            self.ftp_watts = snapshot.ftpWatts > 0 ? snapshot.ftpWatts : nil
            self.max_hr = snapshot.maxHR > 0 ? snapshot.maxHR : nil
            self.resting_hr = snapshot.restingHR > 0 ? snapshot.restingHR : nil
            self.source = Self.normalizedSource(snapshot.sourceRaw)
        }

        private static func normalizedSource(_ raw: String) -> String {
            // Coerce iOS snake-case-ish strings to the values the table CHECK
            // constraint accepts.
            switch raw {
            case "ftp_settings", "hr_settings", "ftp_test", "manual", "sync": raw
            default: "manual"
            }
        }
    }
}

// MARK: - Custom workout templates

struct CustomWorkoutTemplateSyncDomain: SupabaseSyncDomain {
    let name = "custom_workout_templates"
    private static let cursorKey = "mangox.sync.custom_templates.cursor"

    @MainActor
    func push(userId: UUID, client: SupabaseClient, context: ModelContext) async throws {
        let cursor = UserDefaults.standard.object(forKey: Self.cursorKey) as? Date ?? .distantPast
        let descriptor = FetchDescriptor<CustomWorkoutTemplate>(
            predicate: #Predicate { $0.createdAt > cursor },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        let templates = try context.fetch(descriptor)
        guard !templates.isEmpty else { return }

        var newCursor = cursor
        let rows = templates.map { template -> Row in
            if template.createdAt > newCursor { newCursor = template.createdAt }
            return Row(template: template, userId: userId)
        }
        try await client.from("custom_workout_templates").upsert(rows, onConflict: "id").execute()
        UserDefaults.standard.set(newCursor, forKey: Self.cursorKey)
    }

    private struct Row: Codable, Sendable {
        let id: String
        let user_id: String
        let name: String
        let description: String?
        let intervals: AnyJSON
        let created_at: Date

        init(template: CustomWorkoutTemplate, userId: UUID) {
            self.id = template.id.uuidString
            self.user_id = userId.uuidString
            self.name = template.name
            self.description = nil
            self.intervals = (try? JSONDecoder().decode(AnyJSON.self, from: template.intervalsPayload)) ?? .array([])
            self.created_at = template.createdAt
        }
    }
}
