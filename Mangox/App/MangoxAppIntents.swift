import AppIntents
import Foundation

private enum MangoxIntentDeepLink {
    static let indoorRide = URL(string: "mangox://ride/indoor")
    static let outdoorRide = URL(string: "mangox://ride/outdoor")
    static let coach = URL(string: "mangox://coach")
}

struct OpenIndoorRideIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Indoor Ride"
    static let description = IntentDescription("Open Mangox to the indoor ride dashboard.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        guard let url = MangoxIntentDeepLink.indoorRide else {
            return .result()
        }
        return .result(opensIntent: OpenURLIntent(url))
    }
}

struct OpenOutdoorRideIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Outdoor Ride"
    static let description = IntentDescription("Open Mangox to the outdoor ride dashboard.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        guard let url = MangoxIntentDeepLink.outdoorRide else {
            return .result()
        }
        return .result(opensIntent: OpenURLIntent(url))
    }
}

struct OpenCoachIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Coach"
    static let description = IntentDescription("Open Mangox to the coach.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        guard let url = MangoxIntentDeepLink.coach else {
            return .result()
        }
        return .result(opensIntent: OpenURLIntent(url))
    }
}

struct MangoxAppShortcuts: AppShortcutsProvider {
    static let shortcutTileColor: ShortcutTileColor = .orange

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenIndoorRideIntent(),
            phrases: [
                "Open indoor ride in \(.applicationName)",
                "Start indoor ride in \(.applicationName)",
            ],
            shortTitle: "Indoor Ride",
            systemImageName: "figure.indoor.cycle"
        )
        AppShortcut(
            intent: OpenOutdoorRideIntent(),
            phrases: [
                "Open outdoor ride in \(.applicationName)",
                "Start outdoor ride in \(.applicationName)",
            ],
            shortTitle: "Outdoor Ride",
            systemImageName: "figure.outdoor.cycle"
        )
        AppShortcut(
            intent: OpenCoachIntent(),
            phrases: [
                "Open coach in \(.applicationName)",
                "Ask \(.applicationName) coach",
            ],
            shortTitle: "Coach",
            systemImageName: "sparkles"
        )
    }
}
