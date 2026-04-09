// App/LaunchOverlayEnvironment.swift
import SwiftUI

private enum LaunchOverlayEnvironment {
    struct Key: EnvironmentKey {
        static let defaultValue = false
    }
}

extension EnvironmentValues {
    /// True while `LaunchScreenView` covers the root UI (`MangoxApp`).
    var launchOverlayVisible: Bool {
        get { self[LaunchOverlayEnvironment.Key.self] }
        set { self[LaunchOverlayEnvironment.Key.self] = newValue }
    }
}
