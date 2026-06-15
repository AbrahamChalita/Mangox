import Foundation
import SwiftData

@MainActor
final class WorkoutPersistenceRepository: WorkoutPersistenceRepositoryProtocol {
    private let modelContext: ModelContext
    private let modelContainer: ModelContainer
    private var onLocalChange: (() -> Void)?

    init(modelContext: ModelContext, modelContainer: ModelContainer) {
        self.modelContext = modelContext
        self.modelContainer = modelContainer
    }

    func setOnLocalChange(_ block: @escaping () -> Void) {
        onLocalChange = block
    }

    private func notifyLocalChange() {
        onLocalChange?()
    }

    convenience init(modelContainer: ModelContainer) {
        self.init(modelContext: ModelContext(modelContainer), modelContainer: modelContainer)
    }

    convenience init() {
        self.init(
            modelContext: PersistenceContainer.shared.mainContext,
            modelContainer: PersistenceContainer.shared
        )
    }

    // MARK: - Existing methods

    func saveWorkoutAsCustomTemplate(from workout: Workout) throws -> UUID? {
        guard workout.planDayID == nil else { return nil }
        guard let template = WorkoutCustomTemplateBuilder.makeTemplate(from: workout) else {
            return nil
        }

        modelContext.insert(template)
        try modelContext.save()
        notifyLocalChange()
        return template.id
    }

    func saveCustomWorkoutTemplate(name: String, intervals: [IntervalSegment]) throws -> UUID {
        let template = CustomWorkoutTemplate(name: name, intervals: intervals)
        modelContext.insert(template)
        try modelContext.save()
        notifyLocalChange()
        return template.id
    }

    func deleteWorkout(_ workout: Workout) throws {
        if let dayID = workout.planDayID, let planID = workout.planID {
            unmarkPlanDay(dayID, planID: planID)
        }

        modelContext.delete(workout)
        try modelContext.save()
    }

    // MARK: - New methods

    func saveOutdoorRide(workout: Workout, splits: [LapSplit]) throws {
        modelContext.insert(workout)
        for split in splits {
            modelContext.insert(split)
        }
        try modelContext.save()
        MangoxModelNotifications.postWorkoutAggregatesMayHaveChanged()
        notifyLocalChange()
    }

    @discardableResult
    func saveImportedWorkout(_ payload: ImportedWorkoutPayload) throws -> Workout {
        let workout = Workout(startDate: payload.startDate)
        workout.duration = TimeInterval(payload.durationSeconds)
        workout.distance = payload.distanceMeters
        workout.avgPower = payload.avgPower
        workout.maxPower = payload.maxPower
        workout.avgHR = payload.avgHR
        workout.maxHR = payload.maxHR
        workout.avgCadence = averageCadence(from: payload.samples)
        workout.avgSpeed = averageSpeed(from: payload.samples, fallbackDistance: payload.distanceMeters, durationSeconds: payload.durationSeconds)
        workout.endDate = payload.startDate.addingTimeInterval(TimeInterval(payload.durationSeconds))
        workout.status = .completed
        workout.origin = .imported
        workout.importFormat = payload.format
        workout.notes = "Imported from \(payload.format.rawValue.uppercased()) · \(payload.fileName)"
        workout.sampleCount = payload.samples.count
        workout.updatedAt = .now

        let powerSamples = payload.samples.map(\.power).filter { $0 > 0 }
        if !powerSamples.isEmpty {
            let metrics = WorkoutMetricsAggregator.normalizedPowerIntensityAndTSS(
                powerSamples: powerSamples,
                durationSeconds: payload.durationSeconds,
                ftp: Double(PowerZone.ftp)
            )
            workout.normalizedPower = metrics.np
            workout.intensityFactor = metrics.intensityFactor
            workout.tss = metrics.tss
        }

        let lap = LapSplit(lapNumber: 1, startTime: payload.startDate)
        lap.endTime = workout.endDate
        lap.duration = workout.duration
        lap.avgPower = workout.avgPower
        lap.maxPower = workout.maxPower
        lap.avgCadence = workout.avgCadence
        lap.avgSpeed = workout.avgSpeed
        lap.avgHR = workout.avgHR
        lap.distance = workout.distance
        lap.workout = workout

        modelContext.insert(workout)
        modelContext.insert(lap)

        for samplePayload in payload.samples {
            let sample = WorkoutSample(
                timestamp: samplePayload.timestamp,
                elapsedSeconds: samplePayload.elapsedSeconds,
                power: samplePayload.power,
                cadence: samplePayload.cadence,
                speed: samplePayload.speed,
                heartRate: samplePayload.heartRate
            )
            sample.workout = workout
            modelContext.insert(sample)
        }

        try modelContext.save()
        MangoxModelNotifications.postWorkoutAggregatesMayHaveChanged()
        notifyLocalChange()
        return workout
    }

    @discardableResult
    func saveExternalWorkout(_ payload: ExternalWorkoutPayload) throws -> Workout {
        let workout = Workout(startDate: payload.startDate)
        workout.duration = TimeInterval(payload.durationSeconds)
        workout.distance = payload.distanceMeters
        workout.avgPower = payload.avgPower
        workout.maxPower = payload.maxPower
        workout.avgHR = payload.avgHR
        workout.maxHR = payload.maxHR
        workout.avgCadence = payload.avgCadence
        workout.avgSpeed = averageSpeed(
            from: payload.samples,
            fallbackDistance: payload.distanceMeters,
            durationSeconds: payload.durationSeconds
        )
        workout.elevationGain = payload.elevationGainMeters
        workout.normalizedPower = payload.normalizedPower
        workout.intensityFactor = payload.intensityFactor
        workout.tss = payload.tss
        workout.endDate = payload.startDate.addingTimeInterval(TimeInterval(payload.durationSeconds))
        workout.status = .completed
        workout.origin = .imported
        workout.importFormat = payload.format
        workout.externalSource = payload.source
        workout.externalID = payload.externalID
        workout.smartTitle = payload.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        workout.notes = externalImportNotes(source: payload.source, title: payload.title)
        workout.sampleCount = payload.samples.count
        workout.updatedAt = .now

        let lap = LapSplit(lapNumber: 1, startTime: payload.startDate)
        lap.endTime = workout.endDate
        lap.duration = workout.duration
        lap.avgPower = workout.avgPower
        lap.maxPower = workout.maxPower
        lap.avgCadence = workout.avgCadence
        lap.avgSpeed = workout.avgSpeed
        lap.avgHR = workout.avgHR
        lap.distance = workout.distance
        lap.workout = workout

        modelContext.insert(workout)
        modelContext.insert(lap)

        for samplePayload in payload.samples {
            let sample = WorkoutSample(
                timestamp: samplePayload.timestamp,
                elapsedSeconds: samplePayload.elapsedSeconds,
                power: samplePayload.power,
                cadence: samplePayload.cadence,
                speed: samplePayload.speed,
                heartRate: samplePayload.heartRate
            )
            sample.workout = workout
            modelContext.insert(sample)
        }

        try modelContext.save()
        MangoxModelNotifications.postWorkoutAggregatesMayHaveChanged()
        notifyLocalChange()
        return workout
    }

    func mostRecentExternalWorkoutDate(source: ExternalWorkoutSource) throws -> Date? {
        let sourceRaw = source.rawValue
        var descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate {
                $0.externalSourceRaw == sourceRaw && $0.externalID != nil
            },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.startDate
    }

    func fetchExternalWorkout(source: ExternalWorkoutSource, externalID: String) throws -> Workout? {
        let sourceRaw = source.rawValue
        var descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate {
                $0.externalSourceRaw == sourceRaw && $0.externalID == externalID
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func fetchOverlappingWorkout(
        startDate: Date,
        durationSeconds: Int,
        windowSeconds: Int
    ) throws -> Workout? {
        let window = TimeInterval(windowSeconds)
        let earliest = startDate.addingTimeInterval(-window)
        let latest = startDate.addingTimeInterval(window)
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate {
                $0.startDate >= earliest
                    && $0.startDate <= latest
                    && $0.statusRaw == "completed"
            },
            sortBy: [SortDescriptor(\.startDate)]
        )
        let candidates = try modelContext.fetch(descriptor)
        return candidates.first { workout in
            abs(workout.startDate.timeIntervalSince(startDate)) < window
                && abs(Int(workout.duration) - durationSeconds) < 120
        }
    }

    func occupiedPlanDayIDs(planID: String) throws -> Set<String> {
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate {
                $0.planID == planID && $0.planDayID != nil && $0.statusRaw == "completed"
            }
        )
        let workouts = try modelContext.fetch(descriptor)
        return Set(workouts.compactMap(\.planDayID))
    }

    func fetchCustomWorkoutTemplate(id: UUID) throws -> PlanDay? {
        let capturedID = id
        let predicate = #Predicate<CustomWorkoutTemplate> { $0.id == capturedID }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.asPlanDay()
    }

    func fetchSortedSamples(forWorkoutID id: PersistentIdentifier) async -> [WorkoutSampleData] {
        let container = modelContainer
        return await withTaskGroup(
            of: [WorkoutSampleData]?.self,
            returning: [WorkoutSampleData]?.self
        ) { group in
            group.addTask(priority: .userInitiated) {
                guard !Task.isCancelled else { return nil }
                let bgContext = ModelContext(container)
                guard let bgWorkout = bgContext.model(for: id) as? Workout else {
                    return []
                }
                var sortedSamples = bgWorkout.samples
                sortedSamples.sort { $0.elapsedSeconds < $1.elapsedSeconds }
                var projectedSamples: [WorkoutSampleData] = []
                projectedSamples.reserveCapacity(sortedSamples.count)
                for sample in sortedSamples {
                    if Task.isCancelled { return nil }
                    projectedSamples.append(
                        WorkoutSampleData(
                            timestamp: sample.timestamp,
                            elapsedSeconds: sample.elapsedSeconds,
                            power: sample.power,
                            cadence: sample.cadence,
                            speed: sample.speed,
                            heartRate: sample.heartRate
                        )
                    )
                }
                return projectedSamples
            }
            return await group.next() ?? nil
        } ?? []
    }

    // MARK: - Private helpers

    /// Removes `dayID` from the completed set of the matching `TrainingPlanProgress` record.
    /// Previously lived as a static method on `DashboardView`; moved here to keep all
    /// SwiftData writes inside the Data layer and remove the inverted Data → Presentation dependency.
    private func unmarkPlanDay(_ dayID: String, planID: String) {
        let descriptor = FetchDescriptor<TrainingPlanProgress>(
            predicate: #Predicate { $0.planID == planID }
        )
        if let progress = try? modelContext.fetch(descriptor).first {
            progress.completedDayIDs.removeAll { $0 == dayID }
            // The final `try modelContext.save()` in `deleteWorkout` will persist this change
            // together with the workout deletion, so no extra save is needed here.
        }
    }

    private func averageCadence(from samples: [ImportedWorkoutSamplePayload]) -> Double {
        let cadenceSamples = samples.map(\.cadence).filter { $0 > 0 }
        guard !cadenceSamples.isEmpty else { return 0 }
        return cadenceSamples.reduce(0, +) / Double(cadenceSamples.count)
    }

    private func averageSpeed(
        from samples: [ImportedWorkoutSamplePayload],
        fallbackDistance: Double,
        durationSeconds: Int
    ) -> Double {
        let speedSamples = samples.map(\.speed).filter { $0 > 0 }
        if !speedSamples.isEmpty {
            return speedSamples.reduce(0, +) / Double(speedSamples.count)
        }
        guard durationSeconds > 0, fallbackDistance > 0 else { return 0 }
        return (fallbackDistance / Double(durationSeconds)) * 3.6
    }

    private func externalImportNotes(source: ExternalWorkoutSource, title: String?) -> String {
        let service = source == .strava ? "Strava" : "WHOOP"
        if let title, !title.isEmpty {
            return "Imported from \(service) · \(title)"
        }
        return "Imported from \(service)"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
