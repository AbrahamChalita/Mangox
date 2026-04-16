// Core/Utilities/RiderIdentityDisplay.swift
import Foundation

/// Resolves how the rider’s name and profile image appear across the app (local prefs vs Strava).
enum RiderIdentityDisplay {
    /// Header / home title: local name, then Strava, then app default.
    static func resolvedTitle(stravaDisplayName: String?) -> String {
        let local = RidePreferences.shared.riderDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !local.isEmpty { return local }
        if let s = stravaDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            return s
        }
        return "Mangox"
    }

    /// Optional display string for summaries and AI copy — nil when nothing is set (skip “Mangox” as a fake name).
    static func personalizationName(stravaDisplayName: String?) -> String? {
        let local = RidePreferences.shared.riderDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !local.isEmpty { return local }
        let s = stravaDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !s.isEmpty { return s }
        return nil
    }

    /// Profile image: local file wins, then Strava HTTPS URL.
    static func resolvedProfileImageURL(stravaProfileURL: URL?) -> URL? {
        if RiderProfileAvatarStore.hasLocalAvatar {
            return RiderProfileAvatarStore.localAvatarFileURL
        }
        return stravaProfileURL
    }
}
