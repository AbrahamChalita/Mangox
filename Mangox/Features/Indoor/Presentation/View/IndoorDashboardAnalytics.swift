import Foundation
import OSLog

/// Lightweight, privacy-preserving session signals for tuning the indoor ride shell.
enum IndoorDashboardAnalytics {
    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Mangox",
        category: "IndoorDashboard"
    )

    static func compactTabChanged(_ tab: String) {
        log.debug("compact_tab \(tab, privacy: .public)")
    }

    static func milestoneToastShown() {
        log.debug("milestone_toast")
    }
}
