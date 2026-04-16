import SwiftUI

/// Reference-counted scope for screens that need live trainer/sensor metrics in `@Observable` SwiftUI state.
/// BLE/Wi‑Fi still delivers packets to `WorkoutManager` and subscribers; this only reduces Observation traffic
/// when the user is on Home / Calendar / etc.
@MainActor
enum TrainerSensorLiveObservationGate {
    private static var depth = 0

    static var isLiveRouteActive: Bool { depth > 0 }

    static func enterLiveRoute() {
        depth += 1
    }

    static func leaveLiveRoute() {
        depth = max(0, depth - 1)
    }
}

extension View {
    /// Marks a navigation destination where live trainer/sensor metrics should drive SwiftUI observation.
    func sensorLiveRouteScope() -> some View {
        self
            .onAppear { TrainerSensorLiveObservationGate.enterLiveRoute() }
            .onDisappear { TrainerSensorLiveObservationGate.leaveLiveRoute() }
    }
}
