// Core/Networking/OAuth/OAuthSessionStore.swift
import Foundation
import Security

private let oauthSessionExpirySkewSeconds = 90

/// Token fields shared by provider OAuth session payloads persisted in Keychain.
protocol OAuthSessionPayload {
    var accessToken: String { get }
    var refreshToken: String { get }
    var expiresAt: Int { get }
}

/// Serializes token refresh, Keychain persistence, and linked-account save timestamps
/// for OAuth providers (Strava, WHOOP, etc.).
@MainActor
final class OAuthSessionStore<Session: Codable & OAuthSessionPayload> {
    private(set) var session: Session?

    private let keychainAccount: String
    private let localSavedAtKey: String
    private var refreshTask: Task<String, Error>?

    var linkedAccountLocalSavedAt: Date? {
        let timestamp = UserDefaults.standard.double(forKey: localSavedAtKey)
        return timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
    }

    init(keychainAccount: String, localSavedAtKey: String) {
        self.keychainAccount = keychainAccount
        self.localSavedAtKey = localSavedAtKey
    }

    func setSession(_ session: Session?) {
        self.session = session
    }

    func markLinkedAccountSaved(at date: Date) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: localSavedAtKey)
    }

    func clearLocalSavedAt() {
        UserDefaults.standard.removeObject(forKey: localSavedAtKey)
    }

    func exportJSON() -> Data? {
        guard let session else { return nil }
        return try? JSONEncoder().encode(session)
    }

    func persist(
        _ session: Session,
        notifyCloud: Bool = true,
        onCloudNotify: (() -> Void)? = nil
    ) throws {
        let data = try JSONEncoder().encode(session)
        try OAuthKeychainStorage.save(data: data, account: keychainAccount)
        self.session = session
        if notifyCloud {
            markLinkedAccountSaved(at: Date())
            onCloudNotify?()
        }
    }

    func restore(
        decoder: JSONDecoder = JSONDecoder(),
        onRestored: (Session) -> Void,
        onFailure: (Error) -> Void
    ) {
        do {
            guard let data = try OAuthKeychainStorage.read(account: keychainAccount) else {
                return
            }
            let restored = try decoder.decode(Session.self, from: data)
            session = restored
            onRestored(restored)
        } catch {
            onFailure(error)
            _ = try? OAuthKeychainStorage.delete(account: keychainAccount)
        }
    }

    func deleteKeychain() {
        _ = try? OAuthKeychainStorage.delete(account: keychainAccount)
    }

    func validAccessToken(
        noSessionError: @autoclosure () -> Error,
        sessionLostError: @escaping @autoclosure () -> Error,
        refresh: @escaping (String) async throws -> Session,
        onRefreshed: @escaping (Session) -> Void,
        onCloudNotify: (() -> Void)? = nil
    ) async throws -> String {
        guard let current = session else {
            throw noSessionError()
        }

        let now = Int(Date().timeIntervalSince1970)
        if current.expiresAt - now > oauthSessionExpirySkewSeconds {
            return current.accessToken
        }

        if let existing = refreshTask {
            return try await existing.value
        }

        let task = Task<String, Error> { [weak self] in
            guard let self, let current = self.session else {
                throw sessionLostError()
            }
            let refreshed = try await refresh(current.refreshToken)
            try self.persist(refreshed, notifyCloud: true, onCloudNotify: onCloudNotify)
            onRefreshed(refreshed)
            return refreshed.accessToken
        }

        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }
}

// MARK: - Keychain

enum OAuthKeychainStorage {
    enum KeychainError: Error {
        case operationFailed(OSStatus)
    }

    static func save(data: Data, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        if updateStatus != errSecItemNotFound {
            throw KeychainError.operationFailed(updateStatus)
        }

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.operationFailed(addStatus)
        }
    }

    static func read(account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError.operationFailed(status)
        }
        return item as? Data
    }

    static func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.operationFailed(status)
        }
    }
}
