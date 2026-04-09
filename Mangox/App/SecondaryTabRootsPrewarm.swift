// App/SecondaryTabRootsPrewarm.swift
import SwiftUI

/// Prewarms Coach + Settings (SwiftData-heavy views) under the launch screen.
/// Calendar and Stats stay cold until first open so launch doesn't pay Charts +
/// large workout queries twice.
struct SecondaryTabRootsPrewarm: View {
    @State private var coachPath = NavigationPath()
    @State private var settingsPath = NavigationPath()

    var body: some View {
        ZStack {
            NavigationStack(path: $coachPath) {
                CoachTabRootView(navigationPath: $coachPath)
            }
            NavigationStack(path: $settingsPath) {
                SettingsView(navigationPath: $settingsPath)
            }
        }
    }
}
