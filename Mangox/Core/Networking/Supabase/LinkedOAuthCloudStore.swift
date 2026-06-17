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
        let provider_user_id: String?
        let encrypted_payload: String
        let updated_at: String
    }

    private struct LegacyRow: Codable, Sendable {
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
        providerUserId: String?,
        userId: UUID,
        client: SupabaseClient
    ) async throws {
        let encrypted = try UserDataCrypto.encrypt(sessionJSON)
        let timestamp = ISO8601DateFormatter().string(from: Date())
        do {
            let row = Row(
                user_id: userId.uuidString,
                provider: provider.rawValue,
                provider_user_id: providerUserId,
                encrypted_payload: encrypted,
                updated_at: timestamp
            )
            try await client
                .from("linked_oauth_accounts")
                .upsert(row, onConflict: "user_id,provider")
                .execute()
        } catch {
            guard providerUserId != nil, error.localizedDescription.contains("provider_user_id") else {
                throw error
            }
            let legacyRow = LegacyRow(
                user_id: userId.uuidString,
                provider: provider.rawValue,
                encrypted_payload: encrypted,
                updated_at: timestamp
            )
            try await client
                .from("linked_oauth_accounts")
                .upsert(legacyRow, onConflict: "user_id,provider")
                .execute()
        }
    }

    static func fetch(
        provider: LinkedOAuthProvider,
        userId: UUID,
        client: SupabaseClient
    ) async throws -> (sessionJSON: Data, updatedAt: Date, providerUserId: String?)? {
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
        return (decrypted, updatedAt, row.provider_user_id)
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

    private static let updatedAtFormatterFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let updatedAtFormatterStd: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func parseUpdatedAt(_ raw: String) -> Date? {
        if let d = updatedAtFormatterFrac.date(from: raw) { return d }
        return updatedAtFormatterStd.date(from: raw)
    }
}
