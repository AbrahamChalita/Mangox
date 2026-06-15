// Features/Workout/Domain/UseCases/SyncExternalCyclingWorkoutsUseCase.swift
import Foundation
import SwiftData

@MainActor
struct SyncExternalCyclingWorkoutsUseCase {
    let stravaService: StravaService
    let whoopService: WhoopServiceProtocol
    let workoutRepository: WorkoutPersistenceRepositoryProtocol
    let trainingPlanLookupService: TrainingPlanLookupServiceProtocol
    let trainingPlanPersistenceRepository: TrainingPlanPersistenceRepositoryProtocol
    let modelContext: ModelContext

    struct Result: Sendable {
        let imported: Int
        let skipped: Int
        let planDaysCompleted: Int
    }

    private static let staleKey = "mangox.externalCycling.lastSync"
    private static let staleDuration: TimeInterval = 4 * 60 * 60
    private static let overlapWindowSeconds = 300
    private static let initialLookbackDays = 30

    func refreshIfStale() async {
        let last = UserDefaults.standard.object(forKey: Self.staleKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > Self.staleDuration else { return }
        _ = try? await callAsFunction()
    }

    func callAsFunction() async throws -> Result {
        async let strava = importStravaCycling()
        async let whoop = importWhoopCycling()
        let (s, w) = try await (strava, whoop)
        UserDefaults.standard.set(Date(), forKey: Self.staleKey)
        return Result(
            imported: s.imported + w.imported,
            skipped: s.skipped + w.skipped,
            planDaysCompleted: s.planDaysCompleted + w.planDaysCompleted
        )
    }

    /// Imports Strava cycling rides for a single calendar day (local time).
    func importStravaDay(_ date: Date) async throws -> Result {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return .init(imported: 0, skipped: 0, planDaysCompleted: 0)
        }
        let after = calendar.date(byAdding: .second, value: -1, to: dayStart) ?? dayStart
        let partial = try await importStravaCycling(since: after, before: dayEnd)
        return Result(
            imported: partial.imported,
            skipped: partial.skipped,
            planDaysCompleted: partial.planDaysCompleted
        )
    }

    /// Imports Strava + WHOOP cycling rides that fall on the given calendar day.
    func importDay(_ date: Date) async throws -> Result {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return .init(imported: 0, skipped: 0, planDaysCompleted: 0)
        }

        async let strava = importStravaCycling(
            since: calendar.date(byAdding: .second, value: -1, to: dayStart) ?? dayStart,
            before: dayEnd
        )
        async let whoop = importWhoopCycling(since: dayStart, until: dayEnd)
        let (s, w) = try await (strava, whoop)
        return Result(
            imported: s.imported + w.imported,
            skipped: s.skipped + w.skipped,
            planDaysCompleted: s.planDaysCompleted + w.planDaysCompleted
        )
    }

    // MARK: - Strava

    private struct PartialResult {
        var imported = 0
        var skipped = 0
        var planDaysCompleted = 0
    }

    private func importStravaCycling(
        since: Date? = nil,
        before: Date? = nil
    ) async throws -> PartialResult {
        guard stravaService.isConnected else { return PartialResult() }

        let cursor = try workoutRepository.mostRecentExternalWorkoutDate(source: .strava)
        let defaultSince = Calendar.current.date(byAdding: .day, value: -Self.initialLookbackDays, to: Date())!
        let windowStart = since ?? cursor ?? defaultSince

        let activities = try await stravaService.fetchRecentActivities(since: windowStart, before: before)
        var result = PartialResult()

        for activity in activities where StravaActivityMapper.isCycling(activity) {
            let externalID = "\(activity.id)"
            if try workoutRepository.fetchExternalWorkout(source: .strava, externalID: externalID) != nil {
                result.skipped += 1
                continue
            }

            let detail = (try? await stravaService.fetchActivityDetail(id: activity.id)) ?? activity
            let duration = detail.movingTime ?? detail.elapsedTime ?? 0
            guard duration >= minimumValidWorkoutSeconds else {
                result.skipped += 1
                continue
            }

            if let start = detail.startDate,
               try workoutRepository.fetchOverlappingWorkout(
                   startDate: start,
                   durationSeconds: duration,
                   windowSeconds: Self.overlapWindowSeconds
               ) != nil {
                result.skipped += 1
                continue
            }

            let streams = try? await stravaService.fetchActivityStreams(id: activity.id)
            guard let payload = StravaCyclingWorkoutMapper.payload(from: detail, streams: streams) else {
                result.skipped += 1
                continue
            }

            let workout = try workoutRepository.saveExternalWorkout(payload)
            result.imported += 1
            if linkToPlanIfNeeded(workout: workout) {
                result.planDaysCompleted += 1
            }
        }

        return result
    }

    // MARK: - WHOOP

    private func importWhoopCycling(
        since: Date? = nil,
        until: Date? = nil
    ) async throws -> PartialResult {
        guard whoopService.isConnected else { return PartialResult() }

        let cursor = try workoutRepository.mostRecentExternalWorkoutDate(source: .whoop)
        let defaultSince = Calendar.current.date(byAdding: .day, value: -Self.initialLookbackDays, to: Date())!
        let windowStart = since ?? cursor ?? defaultSince
        let windowEnd = until ?? Date()

        let dtos = try await whoopService.fetchRecentWorkouts(since: windowStart, until: windowEnd)
        var result = PartialResult()

        for dto in dtos where WhoopCyclingWorkoutMapper.isCycling(dto) {
            if try workoutRepository.fetchExternalWorkout(source: .whoop, externalID: dto.id) != nil {
                result.skipped += 1
                continue
            }

            guard let payload = WhoopCyclingWorkoutMapper.payload(from: dto) else {
                result.skipped += 1
                continue
            }

            if try workoutRepository.fetchOverlappingWorkout(
                startDate: payload.startDate,
                durationSeconds: payload.durationSeconds,
                windowSeconds: Self.overlapWindowSeconds
            ) != nil {
                result.skipped += 1
                continue
            }

            let workout = try workoutRepository.saveExternalWorkout(payload)
            result.imported += 1
            if linkToPlanIfNeeded(workout: workout) {
                result.planDaysCompleted += 1
            }
        }

        return result
    }

    // MARK: - Plan linking

    @discardableResult
    private func linkToPlanIfNeeded(workout: Workout) -> Bool {
        guard workout.planDayID == nil else { return false }

        let descriptor = FetchDescriptor<TrainingPlanProgress>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        guard let allProgress = try? modelContext.fetch(descriptor), !allProgress.isEmpty else {
            return false
        }

        guard let match = ExternalActivityPlanMatcher.matchAcrossPlans(
            workoutStart: workout.startDate,
            workoutDurationSeconds: Int(workout.duration),
            allProgress: allProgress,
            resolvePlan: { [trainingPlanLookupService] planID in
                trainingPlanLookupService.resolvePlan(planID: planID)
            },
            occupiedDayIDsForPlan: { [workoutRepository] planID in
                (try? workoutRepository.occupiedPlanDayIDs(planID: planID)) ?? []
            }
        ) else {
            return false
        }

        PlanWorkoutCompletion.completePlanLinkedRide(
            workout: workout,
            planID: match.progress.planID,
            dayID: match.day.id,
            planDay: match.day,
            modelContext: modelContext,
            trainingPlanPersistenceRepository: trainingPlanPersistenceRepository,
            source: workout.externalSource?.rawValue ?? "external_import"
        )
        return true
    }
}
