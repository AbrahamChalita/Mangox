// Features/ActivityLog/Presentation/ViewModel/LoggedActivitiesViewModel.swift
import Foundation
import Observation

enum LoggedActivityDateScope: String, CaseIterable, Identifiable, Sendable {
    case today
    case week
    case all
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .today: "Today"
        case .week: "This Week"
        case .all: "All"
        }
    }
}

@Observable
@MainActor
final class LoggedActivitiesViewModel {
    private(set) var activities: [LoggedActivity] = []
    var sourceFilter: LoggedActivitySource? = nil
    var dateScope: LoggedActivityDateScope = .today
    private(set) var isImporting = false
    private(set) var importSummary: String? = nil
    private(set) var errorMessage: String? = nil

    /// When set, the view operates in day-locked mode: scope chips are hidden, all filtering and
    /// imports are pinned to this day. Set from the calendar's per-day "activities" button.
    let lockedDate: Date?

    private let repository: LoggedActivityRepository
    private let importWhoop: ImportWhoopWorkoutsUseCase
    private let importStrava: ImportStravaActivitiesUseCase
    private let syncExternalCycling: SyncExternalCyclingWorkoutsUseCase
    private let whoopConnectedProvider: () -> Bool
    private let stravaConnectedProvider: () -> Bool

    private static let staleKey = "mangox.activityLog.lastImport"
    private static let staleDuration: TimeInterval = 4 * 60 * 60

    var whoopConnected: Bool { whoopConnectedProvider() }
    var stravaConnected: Bool { stravaConnectedProvider() }

    var filteredActivities: [LoggedActivity] {
        let calendar = Calendar.current
        if let lockedDate {
            let start = calendar.startOfDay(for: lockedDate)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? lockedDate
            return activities
                .filter { $0.startDate >= start && $0.startDate < end }
                .sorted { $0.startDate < $1.startDate }
        }
        let now = Date()
        switch dateScope {
        case .today:
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now
            return activities.filter { $0.startDate >= start && $0.startDate < end }
        case .week:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: now) else { return activities }
            return activities.filter { $0.startDate >= interval.start && $0.startDate < interval.end }
        case .all:
            return activities
        }
    }

    /// Day-scope summary used by the locked-day header. Returns total seconds, total distance (m), count.
    var lockedDaySummary: (durationSeconds: Int, distanceMeters: Double, count: Int) {
        let acts = filteredActivities
        let dur = acts.reduce(0) { $0 + $1.durationSeconds }
        let dist = acts.compactMap(\.metrics.distanceMeters).reduce(0, +)
        return (dur, dist, acts.count)
    }

    var activitiesGroupedByWeek: [(weekLabel: String, activities: [LoggedActivity])] {
        let calendar = Calendar.current
        let source = filteredActivities
        let grouped = Dictionary(grouping: source) { activity -> Date in
            calendar.dateInterval(of: .weekOfYear, for: activity.startDate)?.start ?? activity.startDate
        }
        return grouped
            .sorted { $0.key > $1.key }
            .map { (weekStart, items) in
                let label = Self.weekLabel(for: weekStart, calendar: calendar)
                return (weekLabel: label, activities: items.sorted { $0.startDate > $1.startDate })
            }
    }

    init(
        repository: LoggedActivityRepository,
        importWhoop: ImportWhoopWorkoutsUseCase,
        importStrava: ImportStravaActivitiesUseCase,
        syncExternalCycling: SyncExternalCyclingWorkoutsUseCase,
        whoopConnected: @escaping () -> Bool,
        stravaConnected: @escaping () -> Bool,
        lockedDate: Date? = nil
    ) {
        self.repository = repository
        self.importWhoop = importWhoop
        self.importStrava = importStrava
        self.syncExternalCycling = syncExternalCycling
        self.whoopConnectedProvider = whoopConnected
        self.stravaConnectedProvider = stravaConnected
        self.lockedDate = lockedDate
    }

    func dismissImportSummary() {
        importSummary = nil
    }

    func load() {
        do {
            activities = try repository.fetchAll(limit: nil, source: sourceFilter)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ id: UUID) {
        do {
            try repository.delete(id: id)
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func runImportAll() async {
        guard !isImporting else { return }
        isImporting = true
        defer { isImporting = false }
        importSummary = nil
        errorMessage = nil

        async let whoopResult = runWhoopImport()
        async let stravaResult = runStravaImport()
        async let cyclingResult = runExternalCyclingImport()
        let (w, s, c) = await (whoopResult, stravaResult, cyclingResult)

        let crossTrain = (w?.imported ?? 0) + (s?.imported ?? 0)
        let rides = c?.imported ?? 0
        let total = crossTrain + rides
        if total > 0 {
            if rides > 0, crossTrain > 0 {
                importSummary =
                    "Imported \(rides) cycling ride\(rides == 1 ? "" : "s") and \(crossTrain) cross-training activit\(crossTrain == 1 ? "y" : "ies")"
            } else if rides > 0 {
                importSummary = "\(rides) cycling ride\(rides == 1 ? "" : "s") imported"
            } else {
                importSummary = "\(crossTrain) new activit\(crossTrain == 1 ? "y" : "ies") imported"
            }
        } else {
            importSummary = "Already up to date"
        }
        UserDefaults.standard.set(Date(), forKey: Self.staleKey)
        load()
    }

    /// Imports only today's activities (calendar-day window). Doesn't update the global stale cursor —
    /// the user may still want a full sync afterward to backfill missed days.
    func runImportToday() async {
        guard !isImporting else { return }
        isImporting = true
        defer { isImporting = false }
        importSummary = nil
        errorMessage = nil

        async let stravaResult = runStravaTodayImport()
        async let whoopResult = runWhoopImport()
        async let cyclingResult = runExternalCyclingImportDay(Date())
        let (s, w, c) = await (stravaResult, whoopResult, cyclingResult)

        let total = (s?.imported ?? 0) + (w?.imported ?? 0) + (c?.imported ?? 0)
        importSummary = total > 0
            ? "\(total) new activit\(total == 1 ? "y" : "ies") for today"
            : "No new activities today"
        load()
    }

    @discardableResult
    private func runStravaTodayImport() async -> ImportStravaActivitiesUseCase.Result? {
        guard stravaConnected else { return nil }
        do {
            return try await importStrava.importDay(Date())
        } catch {
            errorMessage = "Strava import failed: \(error.localizedDescription)"
            return nil
        }
    }

    /// Imports only the locked day's Strava activities, plus a regular WHOOP refresh (WHOOP has no
    /// per-day endpoint). Used by the day-locked entry from the calendar.
    func runImportLockedDay() async {
        guard let lockedDate else { return }
        guard !isImporting else { return }
        isImporting = true
        defer { isImporting = false }
        importSummary = nil
        errorMessage = nil

        async let stravaResult = runStravaImportForDay(lockedDate)
        async let whoopResult = runWhoopImport()
        async let cyclingResult = runExternalCyclingImportDay(lockedDate)
        let (s, w, c) = await (stravaResult, whoopResult, cyclingResult)

        let total = (s?.imported ?? 0) + (w?.imported ?? 0) + (c?.imported ?? 0)
        importSummary = total > 0
            ? "\(total) new activit\(total == 1 ? "y" : "ies") imported"
            : "Already up to date for this day"
        load()
    }

    @discardableResult
    private func runStravaImportForDay(_ date: Date) async -> ImportStravaActivitiesUseCase.Result? {
        guard stravaConnected else { return nil }
        do {
            return try await importStrava.importDay(date)
        } catch {
            errorMessage = "Strava import failed: \(error.localizedDescription)"
            return nil
        }
    }

    func refreshIfStale() async {
        let last = UserDefaults.standard.object(forKey: Self.staleKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > Self.staleDuration else {
            await syncExternalCycling.refreshIfStale()
            return
        }
        await runImportAll()
    }

    @discardableResult
    private func runExternalCyclingImportDay(_ date: Date) async -> SyncExternalCyclingWorkoutsUseCase.Result? {
        guard whoopConnected || stravaConnected else { return nil }
        do {
            return try await syncExternalCycling.importDay(date)
        } catch {
            errorMessage = "Cycling import failed: \(error.localizedDescription)"
            return nil
        }
    }

    @discardableResult
    private func runExternalCyclingImport() async -> SyncExternalCyclingWorkoutsUseCase.Result? {
        guard whoopConnected || stravaConnected else { return nil }
        do {
            return try await syncExternalCycling()
        } catch {
            errorMessage = "Cycling import failed: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - Private

    @discardableResult
    private func runWhoopImport() async -> ImportWhoopWorkoutsUseCase.Result? {
        guard whoopConnected else { return nil }
        do {
            return try await importWhoop()
        } catch {
            errorMessage = "WHOOP import failed: \(error.localizedDescription)"
            return nil
        }
    }

    @discardableResult
    private func runStravaImport() async -> ImportStravaActivitiesUseCase.Result? {
        guard stravaConnected else { return nil }
        do {
            return try await importStrava()
        } catch {
            errorMessage = "Strava import failed: \(error.localizedDescription)"
            return nil
        }
    }

    private static func weekLabel(for weekStart: Date, calendar: Calendar) -> String {
        let now = Date()
        if calendar.isDate(weekStart, equalTo: now, toGranularity: .weekOfYear) {
            return "This Week"
        }
        let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: now) ?? now
        if calendar.isDate(weekStart, equalTo: lastWeek, toGranularity: .weekOfYear) {
            return "Last Week"
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        let end = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return "\(fmt.string(from: weekStart)) – \(fmt.string(from: end))"
    }
}
