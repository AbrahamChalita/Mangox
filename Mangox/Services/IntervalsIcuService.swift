import Foundation
import Observation
import Security

/// Uploads FIT files to [Intervals.icu](https://intervals.icu) using API key auth.
/// Settings: athlete ID (numeric, from your profile URL) and API key from Settings → API access.
@Observable
final class IntervalsIcuService {

    static let shared = IntervalsIcuService()

    private static let athleteIDKey = "intervals_icu_athlete_id"
    private static let apiKeyKeychainAccount = "intervals_icu_api_key"

    var athleteID: String {
        didSet { UserDefaults.standard.set(athleteID, forKey: Self.athleteIDKey) }
    }

    var apiKey: String {
        didSet { saveAPIKeyToKeychain(apiKey) }
    }

    var lastError: String?

    var isConfigured: Bool {
        !athleteID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private init() {
        self.athleteID = UserDefaults.standard.string(forKey: Self.athleteIDKey) ?? ""
        self.apiKey = Self.loadAPIKeyFromKeychain()
    }

    enum UploadError: LocalizedError {
        case notConfigured
        case invalidResponse(Int)
        case transport(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Add athlete ID and API key in Settings."
            case .invalidResponse(let code): return "Intervals.icu returned HTTP \(code)."
            case .transport(let s): return s
            }
        }
    }

    /// POST multipart `file` to the athlete activities endpoint.
    func uploadFIT(fileURL: URL, name: String?) async throws {
        guard isConfigured else { throw UploadError.notConfigured }

        let base = "https://intervals.icu/api/v1/athlete/\(athleteID)/activities"
        var components = URLComponents(string: base)
        if let name, !name.isEmpty {
            components?.queryItems = [URLQueryItem(name: "name", value: name)]
        }
        guard let url = components?.url else {
            throw UploadError.transport("Bad URL")
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        let filename = fileURL.lastPathComponent

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(try Data(contentsOf: fileURL))
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let auth = "API_KEY:\(apiKey)".data(using: .utf8)!.base64EncodedString()
        request.setValue("Basic \(auth)", forHTTPHeaderField: "Authorization")
        request.httpBody = body

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UploadError.transport("No response")
        }
        guard (200...299).contains(http.statusCode) else {
            throw UploadError.invalidResponse(http.statusCode)
        }
    }

    // MARK: - Keychain

    private func saveAPIKeyToKeychain(_ key: String) {
        guard let data = key.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: Self.apiKeyKeychainAccount,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    private static func loadAPIKeyFromKeychain() -> String {
        // Migrate from UserDefaults if key exists there
        let legacyKey = "intervals_icu_api_key"
        if let legacy = UserDefaults.standard.string(forKey: legacyKey), !legacy.isEmpty {
            IntervalsIcuService.saveToKeychain(legacy)
            UserDefaults.standard.removeObject(forKey: legacyKey)
            return legacy
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: apiKeyKeychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else { return "" }
        return key
    }

    private static func saveToKeychain(_ key: String) {
        guard let data = key.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: apiKeyKeychainAccount,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            SecItemAdd(insert as CFDictionary, nil)
        }
    }
}
