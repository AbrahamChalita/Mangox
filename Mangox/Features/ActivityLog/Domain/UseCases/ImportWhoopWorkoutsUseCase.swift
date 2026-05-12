// Features/ActivityLog/Domain/UseCases/ImportWhoopWorkoutsUseCase.swift
import Foundation

@MainActor
struct ImportWhoopWorkoutsUseCase {
    let whoopService: WhoopServiceProtocol
    let repository: LoggedActivityRepository

    struct Result: Sendable {
        let imported: Int
        let skipped: Int
    }

    func callAsFunction() async throws -> Result {
        guard whoopService.isConnected else { return .init(imported: 0, skipped: 0) }

        let cursor = try repository.mostRecentExternalDate(source: .whoop)
        let since = cursor ?? Calendar.current.date(byAdding: .day, value: -30, to: Date())!

        let dtos = try await whoopService.fetchRecentWorkouts(since: since, until: Date())
        let drafts = dtos.compactMap { WhoopWorkoutMapper.draft(from: $0) }
        let inserted = try repository.upsertImported(drafts)
        return .init(imported: inserted, skipped: drafts.count - inserted)
    }
}
