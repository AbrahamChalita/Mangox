// Features/ActivityLog/Domain/UseCases/ImportStravaActivitiesUseCase.swift
import Foundation

@MainActor
struct ImportStravaActivitiesUseCase {
    let stravaService: StravaService
    let repository: LoggedActivityRepository

    struct Result: Sendable {
        let imported: Int
        let skipped: Int
    }

    /// Full sync — uses the most recent imported activity as cursor; falls back to 30 days.
    func callAsFunction() async throws -> Result {
        guard stravaService.isConnected else { return .init(imported: 0, skipped: 0) }
        let cursor = try repository.mostRecentExternalDate(source: .strava)
        let since = cursor ?? Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        return try await importWindow(since: since, before: nil)
    }

    /// Imports activities only on the given calendar day (local time).
    func importDay(_ date: Date) async throws -> Result {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else {
            return .init(imported: 0, skipped: 0)
        }
        // Strava's `after` is exclusive — pass 1s before window start to include it.
        let after = cal.date(byAdding: .second, value: -1, to: dayStart) ?? dayStart
        return try await importWindow(since: after, before: dayEnd)
    }

    /// Shared window-based import. Pass `before: nil` to fetch up to now.
    /// Stream-derived metrics (best-km split, HR-zone distribution) are NOT computed here —
    /// each activity costs an extra `/streams` call and that quickly burns Strava's 15-min
    /// rate budget on a backfill. They're enriched lazily by `EnrichStravaStreamsUseCase`
    /// when the user actually opens a day-summary view that needs them.
    func importWindow(since: Date, before: Date?) async throws -> Result {
        guard stravaService.isConnected else { return .init(imported: 0, skipped: 0) }

        let activities = try await stravaService.fetchRecentActivities(since: since, before: before)

        var drafts: [LoggedActivityDraft] = []
        for activity in activities where !StravaActivityMapper.isCycling(activity) {
            // Detail call still happens — it's cheap and fills cadence/watts/temp from the
            // richer endpoint, which the summary listing needs.
            let detail = (try? await stravaService.fetchActivityDetail(id: activity.id)) ?? activity
            if let draft = StravaActivityMapper.draft(from: detail, streams: nil) {
                drafts.append(draft)
            }
        }

        let inserted = try repository.upsertImported(drafts)
        return .init(imported: inserted, skipped: drafts.count - inserted)
    }
}
