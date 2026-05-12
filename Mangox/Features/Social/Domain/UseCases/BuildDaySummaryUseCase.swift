// Features/Social/Domain/UseCases/BuildDaySummaryUseCase.swift
import Foundation
import SwiftData

@MainActor
struct BuildDaySummaryUseCase {
    let modelContext: ModelContext
    let activityRepository: LoggedActivityRepository

    func callAsFunction(for date: Date) throws -> DaySummary {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!

        let rideDescriptor = FetchDescriptor<Workout>(
            predicate: #Predicate { $0.startDate >= start && $0.startDate < end },
            sortBy: [SortDescriptor(\.startDate)]
        )
        let rides = try modelContext.fetch(rideDescriptor)

        let allActivities = try activityRepository.fetchAll(limit: nil, source: nil)
            .filter { $0.startDate >= start && $0.startDate < end }

        return DaySummary(date: start, cyclingWorkouts: rides, loggedActivities: allActivities)
    }
}
