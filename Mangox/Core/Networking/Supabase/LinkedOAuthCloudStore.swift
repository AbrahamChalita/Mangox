import Foundation
import Supabase

enum LinkedOAuthProvider: String, Codable, Sendable, CaseIterable {
    case strava
    case whoop
}

/// Persists encrypted Strava/WHOOP session JSON in Supabase for signed-in users.
enum LinkedOAuthCloudStore {
    struct Row: Codable, Sendable {
        let user_id: String
        let provider: String
        let encrypted_payload: String
        let updated_at: String
    }

    enum StoreError: LocalizedError {
        case notConfigured
        case encryptionUnavailable
        case invalidRow

        var errorDescription: String? {
            switch self {
            case .notConfigured: "Cloud backup is not configured."
            case .encryptionUnavailable: "USER_DATA_KEY is missing — cannot back up linked accounts."
            case .invalidRow: "Invalid linked account row from server."
            }
        }
    }

    static func upsert(
        provider: LinkedOAuthProvider,
        sessionJSON: Data,
        userId: UUID,
        client: SupabaseClient
    ) async throws {
        let encrypted = try UserDataCrypto.encrypt(sessionJSON)
        let row = Row(
            user_id: userId.uuidString,
            provider: provider.rawValue,
            encrypted_payload: encrypted,
            updated_at: ISO8601DateFormatter().string(from: Date())
        )
        try await client
            .from("linked_oauth_accounts")
            .upsert(row, onConflict: "user_id,provider")
            .execute()
    }

    static func fetch(
        provider: LinkedOAuthProvider,
        userId: UUID,
        client: SupabaseClient
    ) async throws -> (sessionJSON: Data, updatedAt: Date)? {
        let rows: [Row] = try await client
            .from("linked_oauth_accounts")
            .select()
            .eq("user_id", value: userId.uuidString)
            .eq("provider", value: provider.rawValue)
            .limit(1)
            .execute()
            .value

        guard let row = rows.first else { return nil }
        let decrypted = try UserDataCrypto.decrypt(row.encrypted_payload)
        guard let updatedAt = parseUpdatedAt(row.updated_at) else {
            throw StoreError.invalidRow
        }
        return (decrypted, updatedAt)
    }

    static func delete(
        provider: LinkedOAuthProvider,
        userId: UUID,
        client: SupabaseClient
    ) async throws {
        try await client
            .from("linked_oauth_accounts")
            .delete()
            .eq("user_id", value: userId.uuidString)
            .eq("provider", value: provider.rawValue)
            .execute()
    }

    static func deleteAll(userId: UUID, client: SupabaseClient) async throws {
        try await client
            .from("linked_oauth_accounts")
            .delete()
            .eq("user_id", value: userId.uuidString)
            .execute()
    }

    private static func parseUpdatedAt(_ raw: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: raw) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: raw)
    }
}
