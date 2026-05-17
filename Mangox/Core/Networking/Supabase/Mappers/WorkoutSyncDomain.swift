import Foundation
import Supabase
import SwiftData

/// Syncs completed `Workout` rows together with their `samples` and `laps`.
///
/// Push strategy: track a per-domain "last pushed up to" timestamp in
/// UserDefaults. On each sync, fetch SwiftData rows whose local updatedAt
/// exceeds the cursor, upsert them via Postgrest, then advance the cursor.
struct WorkoutSyncDomain: SupabaseSyncDomain {
    let name = "workouts"

    private static let cursorKey = "mangox.sync.workouts.cursor"
    private static let sampleBatchSize = 500

    @MainActor
    func push(userId: UUID, client: SupabaseClient, context: ModelContext) async throws {
        let cursor = UserDefaults.standard.object(forKey: Self.cursorKey) as? Date ?? .distantPast

        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate { $0.updatedAt > cursor },
            sortBy: [SortDescriptor(\.updatedAt, order: .forward)]
        )
        let workouts = try context.fetch(descriptor)
        guard !workouts.isEmpty else { return }

        var newCursor = cursor

        for workout in workouts {
            // Skip in-progress recordings.
            guard workout.statusRaw == "completed" else { continue }

            let workoutId = try await upsertWorkout(workout: workout, userId: userId, client: client)

            try await pushLaps(workout: workout, workoutId: workoutId, userId: userId, client: client)
            try await pushSamples(workout: workout, workoutId: workoutId, userId: userId, client: client)

            if workout.updatedAt > newCursor { newCursor = workout.updatedAt }
        }

        UserDefaults.standard.set(newCursor, forKey: Self.cursorKey)
    }

    @MainActor
    func pull(userId: UUID, client: SupabaseClient, context: ModelContext) async throws {
        // Pull is a no-op in the first release. Multi-device sync (fetch missing
        // workouts from Postgres into SwiftData) is the natural follow-up.
    }

    // MARK: - Children

    @MainActor
    private func upsertWorkout(workout: Workout, userId: UUID, client: SupabaseClient) async throws -> UUID {
        let workoutRow = WorkoutRow(workout: workout, userId: userId)
        let uploadedRows: [UploadedWorkoutRow] = try await client
            .from("workouts")
            .upsert(workoutRow, onConflict: "user_id,client_id")
            .select("id")
            .execute()
            .value

        guard let uploadedWorkout = uploadedRows.first else {
            throw SyncError.missingUploadedWorkoutId(clientId: workout.id)
        }

        return uploadedWorkout.id
    }

    @MainActor
    private func pushLaps(workout: Workout, workoutId: UUID, userId: UUID, client: SupabaseClient) async throws {
        guard !workout.laps.isEmpty else { return }
        let rows = workout.laps.map { LapRow(lap: $0, workoutId: workoutId, userId: userId) }
        try await client
            .from("workout_laps")
            .upsert(rows, onConflict: "workout_id,lap_number")
            .execute()
    }

    @MainActor
    private func pushSamples(workout: Workout, workoutId: UUID, userId: UUID, client: SupabaseClient) async throws {
        guard !workout.samples.isEmpty else { return }
        let allRows = workout.samples
            .sorted { $0.elapsedSeconds < $1.elapsedSeconds }
            .map { SampleRow(sample: $0, workoutId: workoutId, userId: userId) }

        for chunk in allRows.chunked(into: Self.sampleBatchSize) {
            try await client
                .from("workout_samples")
                .upsert(chunk, onConflict: "workout_id,elapsed_seconds")
                .execute()
        }
    }
}

// MARK: - Row encodings

private struct WorkoutRow: Codable, Sendable {
    let user_id: String
    let client_id: String
    let start_date: Date
    let updated_at: Date
    let end_date: Date?
    let duration_seconds: Int
    let distance_meters: Double
    let elevation_gain_meters: Double
    let avg_power: Double?
    let max_power: Double?
    let normalized_power: Double?
    let avg_cadence_rpm: Double?
    let avg_speed_kmh: Double?
    let avg_heart_rate: Double?
    let max_heart_rate: Double?
    let tss: Double?
    let intensity_factor: Double?
    let rpe: Int?
    let notes: String?
    let smart_title: String?
    let status: String
    let origin: String
    let import_format: String?
    let saved_route_name: String?
    let saved_route_kind: String?
    let planned_route_distance_m: Double?
    let plan_id: String?
    let plan_day_id: String?
    let sample_count: Int
    let lap_count: Int

    init(workout: Workout, userId: UUID) {
        self.user_id = userId.uuidString
        self.client_id = workout.id.uuidString
        self.start_date = workout.startDate
        self.updated_at = workout.updatedAt
        self.end_date = workout.endDate
        self.duration_seconds = Int(workout.duration)
        self.distance_meters = workout.distance
        self.elevation_gain_meters = workout.elevationGain
        self.avg_power = workout.avgPower > 0 ? workout.avgPower : nil
        self.max_power = workout.maxPower > 0 ? Double(workout.maxPower) : nil
        self.normalized_power = workout.normalizedPower > 0 ? workout.normalizedPower : nil
        self.avg_cadence_rpm = workout.avgCadence > 0 ? workout.avgCadence : nil
        self.avg_speed_kmh = workout.avgSpeed > 0 ? workout.avgSpeed : nil
        self.avg_heart_rate = workout.avgHR > 0 ? workout.avgHR : nil
        self.max_heart_rate = workout.maxHR > 0 ? Double(workout.maxHR) : nil
        self.tss = workout.tss > 0 ? workout.tss : nil
        self.intensity_factor = workout.intensityFactor > 0 ? workout.intensityFactor : nil
        self.rpe = workout.rpe > 0 ? workout.rpe : nil
        self.notes = workout.notes.isEmpty ? nil : workout.notes
        self.smart_title = workout.smartTitle
        self.status = workout.statusRaw
        self.origin = workout.originRaw
        self.import_format = workout.importFormatRaw
        self.saved_route_name = workout.savedRouteName
        self.saved_route_kind = workout.savedRouteKindRaw
        self.planned_route_distance_m = workout.plannedRouteDistanceMeters > 0 ? workout.plannedRouteDistanceMeters : nil
        self.plan_id = workout.planID
        self.plan_day_id = workout.planDayID
        self.sample_count = workout.sampleCount
        self.lap_count = workout.laps.count
    }
}

private struct UploadedWorkoutRow: Decodable, Sendable {
    let id: UUID
}

private struct LapRow: Codable, Sendable {
    let workout_id: String
    let user_id: String
    let lap_number: Int
    let start_time: Date
    let end_time: Date?
    let duration_seconds: Int
    let distance_meters: Double
    let avg_power: Double?
    let max_power: Double?
    let avg_cadence_rpm: Double?
    let avg_speed_kmh: Double?
    let avg_heart_rate: Double?

    init(lap: LapSplit, workoutId: UUID, userId: UUID) {
        self.workout_id = workoutId.uuidString
        self.user_id = userId.uuidString
        self.lap_number = lap.lapNumber
        self.start_time = lap.startTime
        self.end_time = lap.endTime
        self.duration_seconds = Int(lap.duration)
        self.distance_meters = lap.distance
        self.avg_power = lap.avgPower > 0 ? lap.avgPower : nil
        self.max_power = lap.maxPower > 0 ? Double(lap.maxPower) : nil
        self.avg_cadence_rpm = lap.avgCadence > 0 ? lap.avgCadence : nil
        self.avg_speed_kmh = lap.avgSpeed > 0 ? lap.avgSpeed : nil
        self.avg_heart_rate = lap.avgHR > 0 ? lap.avgHR : nil
    }
}

private struct SampleRow: Codable, Sendable {
    let workout_id: String
    let user_id: String
    let elapsed_seconds: Int
    let recorded_at: Date
    let power: Double?
    let cadence_rpm: Double?
    let speed_kmh: Double?
    let heart_rate: Double?

    init(sample: WorkoutSample, workoutId: UUID, userId: UUID) {
        self.workout_id = workoutId.uuidString
        self.user_id = userId.uuidString
        self.elapsed_seconds = sample.elapsedSeconds
        self.recorded_at = sample.timestamp
        self.power = sample.power > 0 ? Double(sample.power) : nil
        self.cadence_rpm = sample.cadence > 0 ? sample.cadence : nil
        self.speed_kmh = sample.speed > 0 ? sample.speed : nil
        self.heart_rate = sample.heartRate > 0 ? Double(sample.heartRate) : nil
    }
}

// MARK: - Helpers

private enum SyncError: LocalizedError {
    case missingUploadedWorkoutId(clientId: UUID)

    var errorDescription: String? {
        switch self {
        case let .missingUploadedWorkoutId(clientId):
            return "Supabase did not return an id for uploaded workout client_id \(clientId.uuidString)."
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
