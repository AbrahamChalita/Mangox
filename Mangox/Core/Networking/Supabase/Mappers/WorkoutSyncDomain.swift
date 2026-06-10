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
        let remoteRows: [PulledWorkoutRow] = try await client
            .from("workouts")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("updated_at", ascending: false)
            .limit(500)
            .execute()
            .value

        guard !remoteRows.isEmpty else { return }

        var didChange = false
        for remote in remoteRows {
            guard remote.status == "completed" else { continue }
            guard let clientID = remote.client_id else { continue }

            let capturedID = clientID
            var descriptor = FetchDescriptor<Workout>(
                predicate: #Predicate { $0.id == capturedID }
            )
            descriptor.fetchLimit = 1
            let existing = try context.fetch(descriptor).first

            if let existing {
                guard remote.updated_at > existing.updatedAt else { continue }
                applyRemoteSummary(remote, to: existing)
                didChange = true
                if shouldPullChildren(remote: remote, local: existing) {
                    try await pullChildren(
                        remote: remote,
                        local: existing,
                        userId: userId,
                        client: client,
                        context: context
                    )
                }
            } else {
                let workout = makeLocalWorkout(from: remote, clientID: clientID)
                context.insert(workout)
                didChange = true
                if remote.lap_count > 0 || remote.sample_count > 0 {
                    try await pullChildren(
                        remote: remote,
                        local: workout,
                        userId: userId,
                        client: client,
                        context: context
                    )
                }
            }
        }

        if didChange {
            try context.save()
            MangoxModelNotifications.postWorkoutAggregatesMayHaveChanged()
        }
    }

    // MARK: - Pull helpers

    @MainActor
    private func shouldPullChildren(remote: PulledWorkoutRow, local: Workout) -> Bool {
        if remote.sample_count > 0, local.sampleCount < remote.sample_count { return true }
        if remote.lap_count > 0, local.laps.count < remote.lap_count { return true }
        return false
    }

    @MainActor
    private func makeLocalWorkout(from remote: PulledWorkoutRow, clientID: UUID) -> Workout {
        let workout = Workout(
            id: clientID,
            startDate: remote.start_date,
            planDayID: remote.plan_day_id,
            planID: remote.plan_id
        )
        applyRemoteSummary(remote, to: workout)
        return workout
    }

    @MainActor
    private func applyRemoteSummary(_ remote: PulledWorkoutRow, to workout: Workout) {
        workout.startDate = remote.start_date
        workout.updatedAt = remote.updated_at
        workout.endDate = remote.end_date
        workout.duration = TimeInterval(remote.duration_seconds)
        workout.distance = remote.distance_meters
        workout.elevationGain = remote.elevation_gain_meters
        workout.avgPower = remote.avg_power ?? 0
        workout.maxPower = Int(remote.max_power ?? 0)
        workout.normalizedPower = remote.normalized_power ?? 0
        workout.avgCadence = remote.avg_cadence_rpm ?? 0
        workout.avgSpeed = remote.avg_speed_kmh ?? 0
        workout.avgHR = remote.avg_heart_rate ?? 0
        workout.maxHR = Int(remote.max_heart_rate ?? 0)
        workout.tss = remote.tss ?? 0
        workout.intensityFactor = remote.intensity_factor ?? 0
        workout.rpe = remote.rpe ?? 0
        workout.notes = remote.notes ?? ""
        workout.smartTitle = remote.smart_title
        workout.statusRaw = remote.status
        workout.originRaw = remote.origin
        workout.importFormatRaw = remote.import_format
        workout.savedRouteName = remote.saved_route_name
        workout.savedRouteKindRaw = remote.saved_route_kind
        workout.plannedRouteDistanceMeters = remote.planned_route_distance_m ?? 0
        workout.planID = remote.plan_id
        workout.planDayID = remote.plan_day_id
        workout.sampleCount = remote.sample_count
    }

    @MainActor
    private func pullChildren(
        remote: PulledWorkoutRow,
        local: Workout,
        userId: UUID,
        client: SupabaseClient,
        context: ModelContext
    ) async throws {
        let serverWorkoutID = remote.id

        if remote.lap_count > 0, local.laps.isEmpty {
            let lapRows: [PulledLapRow] = try await client
                .from("workout_laps")
                .select()
                .eq("workout_id", value: serverWorkoutID.uuidString)
                .order("lap_number", ascending: true)
                .execute()
                .value

            for lapRow in lapRows {
                let lap = LapSplit(lapNumber: lapRow.lap_number, startTime: lapRow.start_time)
                lap.endTime = lapRow.end_time
                lap.duration = TimeInterval(lapRow.duration_seconds)
                lap.distance = lapRow.distance_meters ?? 0
                lap.avgPower = lapRow.avg_power ?? 0
                lap.maxPower = Int(lapRow.max_power ?? 0)
                lap.avgCadence = lapRow.avg_cadence_rpm ?? 0
                lap.avgSpeed = lapRow.avg_speed_kmh ?? 0
                lap.avgHR = lapRow.avg_heart_rate ?? 0
                lap.workout = local
                context.insert(lap)
            }
        }

        if remote.sample_count > 0, local.samples.count < remote.sample_count {
            var offset = 0
            while offset < remote.sample_count {
                let end = min(offset + Self.sampleBatchSize - 1, remote.sample_count - 1)
                let sampleRows: [PulledSampleRow] = try await client
                    .from("workout_samples")
                    .select()
                    .eq("workout_id", value: serverWorkoutID.uuidString)
                    .order("elapsed_seconds", ascending: true)
                    .range(from: offset, to: end)
                    .execute()
                    .value

                guard !sampleRows.isEmpty else { break }

                for sampleRow in sampleRows {
                    let sample = WorkoutSample(
                        timestamp: sampleRow.recorded_at ?? remote.start_date,
                        elapsedSeconds: sampleRow.elapsed_seconds,
                        power: Int(sampleRow.power ?? 0),
                        cadence: sampleRow.cadence_rpm ?? 0,
                        speed: sampleRow.speed_kmh ?? 0,
                        heartRate: Int(sampleRow.heart_rate ?? 0)
                    )
                    sample.workout = local
                    context.insert(sample)
                }

                offset += sampleRows.count
                if sampleRows.count < Self.sampleBatchSize { break }
            }
            local.sampleCount = max(local.sampleCount, local.samples.count)
        }
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

private struct PulledWorkoutRow: Decodable, Sendable {
    let id: UUID
    let client_id: UUID?
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
}

private struct PulledLapRow: Decodable, Sendable {
    let lap_number: Int
    let start_time: Date
    let end_time: Date?
    let duration_seconds: Int
    let distance_meters: Double?
    let avg_power: Double?
    let max_power: Double?
    let avg_cadence_rpm: Double?
    let avg_speed_kmh: Double?
    let avg_heart_rate: Double?
}

private struct PulledSampleRow: Decodable, Sendable {
    let elapsed_seconds: Int
    let recorded_at: Date?
    let power: Double?
    let cadence_rpm: Double?
    let speed_kmh: Double?
    let heart_rate: Double?
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
