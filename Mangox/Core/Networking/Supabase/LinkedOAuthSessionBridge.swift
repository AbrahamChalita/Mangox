import Foundation
import Supabase

/// Coordinates encrypted WHOOP/Strava session backup and restore for signed-in users.
@MainActor
final class LinkedOAuthSessionBridge {
    private weak var strava: StravaService?
    private weak var whoop: WhoopService?
    private let userId: () -> UUID?

    init(
        strava: StravaService,
        whoop: WhoopService,
        userId: @escaping () -> UUID?
    ) {
        self.strava = strava
        self.whoop = whoop
        self.userId = userId
    }

    func pushLocalSessionsToCloud() async {
        guard let userId = userId(), let client = MangoxSupabase.shared else { return }
        for provider in LinkedOAuthProvider.allCases {
            await push(provider: provider, userId: userId, client: client)
        }
    }

    func restoreSessionsFromCloud() async {
        guard let userId = userId(), let client = MangoxSupabase.shared else { return }
        for provider in LinkedOAuthProvider.allCases {
            await restore(provider: provider, userId: userId, client: client)
        }
    }

    func deleteCloudSession(provider: LinkedOAuthProvider) async {
        guard let userId = userId(), let client = MangoxSupabase.shared else { return }
        try? await LinkedOAuthCloudStore.delete(provider: provider, userId: userId, client: client)
    }

    func deleteAllCloudSessions() async {
        guard let userId = userId(), let client = MangoxSupabase.shared else { return }
        try? await LinkedOAuthCloudStore.deleteAll(userId: userId, client: client)
    }

    func pushProviderToCloud(_ provider: LinkedOAuthProvider) async {
        guard let userId = userId(), let client = MangoxSupabase.shared else { return }
        await push(provider: provider, userId: userId, client: client)
    }

    private func push(provider: LinkedOAuthProvider, userId: UUID, client: SupabaseClient) async {
        guard let json = sessionJSON(for: provider) else { return }
        let localSavedAt = localSavedAt(for: provider)
        do {
            if let remote = try await LinkedOAuthCloudStore.fetch(
                provider: provider,
                userId: userId,
                client: client
            ), let localSavedAt, localSavedAt <= remote.updatedAt {
                return
            }
            try await LinkedOAuthCloudStore.upsert(
                provider: provider,
                sessionJSON: json,
                userId: userId,
                client: client
            )
        } catch {
            #if DEBUG
            print("[LinkedOAuth] push \(provider.rawValue) failed: \(error)")
            #endif
        }
    }

    private func restore(provider: LinkedOAuthProvider, userId: UUID, client: SupabaseClient) async {
        do {
            guard let remote = try await LinkedOAuthCloudStore.fetch(
                provider: provider,
                userId: userId,
                client: client
            ) else { return }

            switch provider {
            case .strava:
                strava?.restoreSessionFromCloudIfNeeded(
                    sessionJSON: remote.sessionJSON,
                    remoteUpdatedAt: remote.updatedAt
                )
            case .whoop:
                whoop?.restoreSessionFromCloudIfNeeded(
                    sessionJSON: remote.sessionJSON,
                    remoteUpdatedAt: remote.updatedAt
                )
            }
        } catch {
            #if DEBUG
            print("[LinkedOAuth] restore \(provider.rawValue) failed: \(error)")
            #endif
        }
    }

    private func localSavedAt(for provider: LinkedOAuthProvider) -> Date? {
        switch provider {
        case .strava: strava?.linkedAccountLocalSavedAt
        case .whoop: whoop?.linkedAccountLocalSavedAt
        }
    }

    private func sessionJSON(for provider: LinkedOAuthProvider) -> Data? {
        switch provider {
        case .strava: strava?.exportSessionJSONForCloudBackup()
        case .whoop: whoop?.exportSessionJSONForCloudBackup()
        }
    }
}
