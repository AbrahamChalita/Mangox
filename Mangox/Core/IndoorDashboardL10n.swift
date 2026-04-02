import Foundation

/// Centralized localized copy for the indoor ride dashboard.
enum IndoorDashboardL10n {
    static var freeRide: String { String(localized: "indoor.mode.free_ride") }
    static var route: String { String(localized: "indoor.mode.route") }
    static var gpxHint: String { String(localized: "indoor.mode.gpx_hint") }

    static var livePerformanceTitle: String { String(localized: "indoor.live_performance.title") }
    static var sessionStatsTitle: String { String(localized: "indoor.session_stats.title") }
    static var sessionStatsExpandHint: String { String(localized: "indoor.session_stats.expand_hint") }
    static var ftpEstimatedHint: String { String(localized: "indoor.ftp.estimated_hint") }

    static var powerGraphTitle: String { String(localized: "indoor.power_graph.title") }
    static var powerGraphEmpty: String { String(localized: "indoor.power_graph.empty") }
    static var powerGraphEmptyA11y: String { String(localized: "indoor.power_graph.empty_accessibility") }

    static var trainerRouteSimFooter: String { String(localized: "indoor.trainer.route_sim_footer") }
}
