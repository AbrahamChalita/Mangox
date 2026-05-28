import Foundation
import Supabase
import SwiftData

/// Pulls encrypted Strava/WHOOP sessions from cloud on sign-in; pushes local sessions after other domains.
struct LinkedOAuthSyncDomain: SupabaseSyncDomain {
    let name = "linked_oauth_accounts"
    let bridge: LinkedOAuthSessionBridge

    @MainActor
    func push(userId: UUID, client: SupabaseClient, context: ModelContext) async throws {
        _ = userId
        _ = client
        _ = context
        await bridge.pushLocalSessionsToCloud()
    }

    @MainActor
    func pull(userId: UUID, client: SupabaseClient, context: ModelContext) async throws {
        _ = userId
        _ = client
        _ = context
        await bridge.restoreSessionsFromCloud()
    }
}
