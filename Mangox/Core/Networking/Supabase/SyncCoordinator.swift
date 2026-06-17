import Foundation
import Observation
import Supabase
import SwiftData

/// One unit of bidirectional sync — a Postgres table backed by a SwiftData model.
///
/// Push uploads local rows; pull downloads remote rows newer than what we have
/// locally. Implementations should be idempotent (use upsert by primary key).
protocol SupabaseSyncDomain: Sendable {
    /// Stable label for logs / error reporting.
    var name: String { get }

    /// Push local rows to Postgres.
    @MainActor func push(userId: UUID, client: SupabaseClient, context: ModelContext) async throws

    /// Pull rows from Postgres into SwiftData. Optional — settings-style domains
    /// that are write-mostly from the device may leave this empty.
    @MainActor func pull(userId: UUID, client: SupabaseClient, context: ModelContext) async throws
}

extension SupabaseSyncDomain {
    @MainActor func pull(userId: UUID, client: SupabaseClient, context: ModelContext) async throws {}
}

// MARK: - Coordinator

@MainActor
@Observable
final class SyncCoordinator {
    enum SyncState: Equatable {
        case idle
        case running
        case error(String)
    }

    /// UserDefaults keys used by sync domains to track per-domain cursors.
    /// Centralized here so signOut() can clear them all in one place.
    static let cursorKeys: [String] = [
        "mangox.sync.workouts.cursor",
        "mangox.sync.chat.cursor",
        "mangox.sync.ai_plans.cursor",
        "mangox.sync.zone_snapshots.cursor",
        "mangox.sync.custom_templates.cursor",
        "mangox.sync.logged_activities.cursor",
    ]

    private(set) var state: SyncState = .idle
    private(set) var lastSyncedAt: Date?

    private let auth: AuthState
    private let context: ModelContext
    private let domains: [SupabaseSyncDomain]
    let linkedOAuthBridge: LinkedOAuthSessionBridge?

    private var debounceTask: Task<Void, Never>?
    private var authObservationTask: Task<Void, Never>?

    init(
        auth: AuthState,
        context: ModelContext,
        domains: [SupabaseSyncDomain],
        linkedOAuthBridge: LinkedOAuthSessionBridge? = nil
    ) {
        self.auth = auth
        self.context = context
        self.domains = domains
        self.linkedOAuthBridge = linkedOAuthBridge
        startObservingAuth()
    }

    // MARK: - Public API

    /// Run a full push + pull cycle. Safe to call repeatedly; concurrent calls coalesce.
    func syncNow() async {
        guard MangoxSupabase.isConfigured else { return }
        guard let client = MangoxSupabase.shared else { return }
        guard let userId = auth.userId else { return }
        guard state != .running else { return }

        state = .running
        defer {
            if case .running = state { state = .idle }
        }

        var firstError: Error?
        for domain in domains {
            do {
                try await domain.push(userId: userId, client: client, context: context)
            } catch {
                firstError = firstError ?? error
                #if DEBUG
                print("[Sync] push failed: \(domain.name) — \(error)")
                #endif
            }
        }
        // Restore Strava/WHOOP tokens before other pulls so a fresh install can import.
        var linkedOAuth: [SupabaseSyncDomain] = []
        var otherDomains: [SupabaseSyncDomain] = []
        for domain in domains {
            if domain.name == "linked_oauth_accounts" {
                linkedOAuth.append(domain)
            } else {
                otherDomains.append(domain)
            }
        }
        for domain in linkedOAuth + otherDomains {
            do {
                try await domain.pull(userId: userId, client: client, context: context)
            } catch {
                firstError = firstError ?? error
                #if DEBUG
                print("[Sync] pull failed: \(domain.name) — \(error)")
                #endif
            }
        }

        if let firstError {
            state = .error((firstError as? LocalizedError)?.errorDescription ?? firstError.localizedDescription)
        } else {
            lastSyncedAt = Date()
            auth.lastSyncedAt = lastSyncedAt
            state = .idle
        }
    }

    /// Coalesced push triggered by local edits. Waits ~1.5s to bundle bursts.
    func notifyLocalChange() {
        guard auth.isSignedIn else { return }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    /// Sign the user out locally. Cloud data is preserved server-side; local
    /// SwiftData stays intact. Sync cursors are cleared so the next sign-in
    /// (which may be a different account) re-uploads the entire local store.
    func signOut() async {
        guard let client = MangoxSupabase.shared else { return }
        try? await client.auth.signOut()
        Self.clearAllCursors()
        lastSyncedAt = nil
        auth.lastSyncedAt = nil
        state = .idle
    }

    static func clearAllCursors() {
        for key in cursorKeys { UserDefaults.standard.removeObject(forKey: key) }
    }

    // MARK: - Auth observation

    private func startObservingAuth() {
        guard let client = MangoxSupabase.shared else { return }
        authObservationTask = Task { [weak self] in
            for await change in client.auth.authStateChanges {
                guard let self else { return }
                await self.handleAuthChange(event: change.event, session: change.session)
            }
        }
    }

    private func handleAuthChange(event: AuthChangeEvent, session: Session?) async {
        switch event {
        case .signedIn, .initialSession:
            // Skip expired sessions surfaced by emitLocalSessionAsInitialSession.
            guard let session, !session.isExpired else { return }
            await syncNow()
        case .signedOut, .userDeleted:
            // Cursor cleanup happens in signOut(); this branch covers external
            // sign-outs (token revoked, account deleted from another device).
            Self.clearAllCursors()
        default:
            break
        }
    }
}
