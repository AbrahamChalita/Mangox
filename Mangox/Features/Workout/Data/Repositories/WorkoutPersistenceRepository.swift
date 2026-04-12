import Foundation
import SwiftData

@MainActor
final class WorkoutPersistenceRepository: WorkoutPersistenceRepositoryProtocol {
    private let modelContext: ModelContext
    private let modelContainer: ModelContainer

    init(modelContext: ModelContext, modelContainer: ModelContainer) {
        self.modelContext = modelContext
        self.modelContainer = modelContainer
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
        return template.id
    }

    func saveCustomWorkoutTemplate(name: String, intervals: [IntervalSegment]) throws -> UUID {
        let template = CustomWorkoutTemplate(name: name, intervals: intervals)
        modelContext.insert(template)
        try modelContext.save()
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
        return workout
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
        return await Task.detached(priority: .userInitiated) {
            let bgContext = ModelContext(container)
            guard let bgWorkout = bgContext.model(for: id) as? Workout else {
                return [WorkoutSampleData]()
            }
            let sortedSamples = bgWorkout.samples.sorted { $0.elapsedSeconds < $1.elapsedSeconds }
            return sortedSamples.map { sample in
                WorkoutSampleData(
                    timestamp: sample.timestamp,
                    elapsedSeconds: sample.elapsedSeconds,
                    power: sample.power,
                    cadence: sample.cadence,
                    speed: sample.speed,
                    heartRate: sample.heartRate
                )
            }
        }.value
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
}
