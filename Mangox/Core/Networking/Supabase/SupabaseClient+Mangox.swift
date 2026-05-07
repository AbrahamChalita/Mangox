import Foundation
import Supabase

/// Lazy singleton wrapping the Supabase client.
///
/// Reads `SUPABASE_URL_HOST` and `SUPABASE_PUBLISHABLE_KEY` from `Info.plist`
/// (populated from `Config/App.xcconfig`). If either is missing the client is
/// `nil` and the app behaves as fully-local — sync paths short-circuit safely.
enum MangoxSupabase {
    static let shared: SupabaseClient? = {
        guard
            let host = infoString("SUPABASE_URL_HOST"),
            let key  = infoString("SUPABASE_PUBLISHABLE_KEY"),
            let url  = URL(string: "https://\(host)")
        else {
            #if DEBUG
            print("[MangoxSupabase] Disabled: SUPABASE_URL_HOST / SUPABASE_PUBLISHABLE_KEY missing.")
            #endif
            return nil
        }

        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: key,
            options: SupabaseClientOptions(
                auth: SupabaseClientOptions.AuthOptions(
                    flowType: .pkce,
                    autoRefreshToken: true,
                    // Opt into supabase-swift's upcoming behavior: emit the
                    // locally stored session as `.initialSession` regardless of
                    // expiration. Listeners must check `session.isExpired`.
                    // See https://github.com/supabase/supabase-swift/pull/822
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }()

    static var isConfigured: Bool { shared != nil }

    static var projectHostForDiagnostics: String {
        infoString("SUPABASE_URL_HOST") ?? "unconfigured"
    }
}

private func infoString(_ key: String) -> String? {
    guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    // Strip out unresolved `$(VAR)` placeholders.
    if trimmed.hasPrefix("$(") && trimmed.hasSuffix(")") { return nil }
    return trimmed
}
