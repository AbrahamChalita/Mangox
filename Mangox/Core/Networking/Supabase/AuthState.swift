import Foundation
import Observation
import Supabase

/// Observable wrapper around the Supabase auth session.
///
/// Holds the current user's id and email when signed in. UI binds to this
/// directly; the rest of the sync stack reads `userId` and short-circuits
/// when it is `nil`.
@MainActor
@Observable
final class AuthState {
    enum Status: Equatable {
        case signedOut
        case signedIn(userId: UUID, email: String?)
        case signingIn
        case error(String)
    }

    private(set) var status: Status = .signedOut

    /// Last sync time, surfaced in the Account row.
    var lastSyncedAt: Date?

    /// Pending error message for the Account view to display.
    var pendingError: String?

    private var observationTask: Task<Void, Never>?

    /// Convenience accessors.
    var userId: UUID? {
        if case .signedIn(let id, _) = status { return id }
        return nil
    }
    var email: String? {
        if case .signedIn(_, let email) = status { return email }
        return nil
    }
    var isSignedIn: Bool { userId != nil }

    init() {
        guard MangoxSupabase.isConfigured else { return }
        startObserving()
        Task { await restoreSession() }
    }

    private func startObserving() {
        guard let client = MangoxSupabase.shared else { return }
        observationTask?.cancel()
        observationTask = Task { [weak self] in
            for await change in client.auth.authStateChanges {
                guard let self else { return }
                self.applyAuthChange(event: change.event, session: change.session)
            }
        }
    }

    private func restoreSession() async {
        guard let client = MangoxSupabase.shared else { return }
        do {
            let session = try await client.auth.session
            applyAuthChange(event: .initialSession, session: session)
        } catch {
            // No persisted session — stay signed out silently.
            status = .signedOut
        }
    }

    private func applyAuthChange(event: AuthChangeEvent, session: Session?) {
        switch event {
        case .signedOut, .userDeleted:
            status = .signedOut
        case .signedIn, .tokenRefreshed, .userUpdated, .initialSession:
            // With emitLocalSessionAsInitialSession=true, an expired stored
            // session will arrive as `.initialSession`; treat it as signed-out.
            guard let session, !session.isExpired else {
                status = .signedOut
                return
            }
            status = .signedIn(userId: session.user.id, email: session.user.email)
        default:
            break
        }
    }

    func setSigningIn() { status = .signingIn }

    func reportError(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        pendingError = message
        // Restore the previous status if we were mid-flight.
        if case .signingIn = status { status = .signedOut }
    }
}
