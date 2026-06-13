import Foundation
import FoundationModels
import Security

// MARK: - Third-party LanguageModel providers (replaces Mangox Cloud fallback tier)

/// Vendor implementing Apple's `LanguageModel` protocol via SPM (Anthropic / Google packages).
enum MangoxCoachThirdPartyProvider: String, CaseIterable, Sendable {
    case disabled
    case anthropic
    case google

    var displayName: String {
        switch self {
        case .disabled: return "Disabled"
        case .anthropic: return "Anthropic (Claude)"
        case .google: return "Google (Gemini)"
        }
    }

    var settingsFootnote: String {
        switch self {
        case .disabled:
            return "Uses Mangox Cloud when Private Cloud Compute is unavailable."
        case .anthropic:
            return "Add the Anthropic Foundation Models Swift package, then enter your API key. Billed by Anthropic — not covered by Apple's free PCC tier."
        case .google:
            return "Add the Google Foundation Models Swift package, then enter your API key. Billed by Google — not covered by Apple's free PCC tier."
        }
    }
}

enum MangoxCoachLanguageModelProviderDefaults {
    static let providerKey = "MangoxCoachThirdPartyProvider"
    static let planCloudFallbackKey = "MangoxCoachPlanCloudFallbackEnabled"
    static let anthropicKeychainAccount = "mangox_coach_anthropic_api_key"
    static let googleKeychainAccount = "mangox_coach_google_api_key"
}

enum MangoxCoachLanguageModelProviderSupport {

    static var selectedProvider: MangoxCoachThirdPartyProvider {
        get {
            let raw = UserDefaults.standard.string(forKey: MangoxCoachLanguageModelProviderDefaults.providerKey) ?? ""
            return MangoxCoachThirdPartyProvider(rawValue: raw) ?? .disabled
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: MangoxCoachLanguageModelProviderDefaults.providerKey)
        }
    }

    static var isThirdPartyFallbackConfigured: Bool {
        guard selectedProvider != .disabled else { return false }
        return !(apiKey(for: selectedProvider)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    static func apiKey(for provider: MangoxCoachThirdPartyProvider) -> String? {
        switch provider {
        case .disabled: return nil
        case .anthropic:
            return MangoxCoachProviderKeychain.read(account: MangoxCoachLanguageModelProviderDefaults.anthropicKeychainAccount)
        case .google:
            return MangoxCoachProviderKeychain.read(account: MangoxCoachLanguageModelProviderDefaults.googleKeychainAccount)
        }
    }

    static func saveAPIKey(_ key: String, for provider: MangoxCoachThirdPartyProvider) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        switch provider {
        case .disabled: break
        case .anthropic:
            MangoxCoachProviderKeychain.save(trimmed, account: MangoxCoachLanguageModelProviderDefaults.anthropicKeychainAccount)
        case .google:
            MangoxCoachProviderKeychain.save(trimmed, account: MangoxCoachLanguageModelProviderDefaults.googleKeychainAccount)
        }
    }

    static func clearAPIKey(for provider: MangoxCoachThirdPartyProvider) {
        switch provider {
        case .disabled: break
        case .anthropic:
            _ = try? MangoxCoachProviderKeychain.delete(account: MangoxCoachLanguageModelProviderDefaults.anthropicKeychainAccount)
        case .google:
            _ = try? MangoxCoachProviderKeychain.delete(account: MangoxCoachLanguageModelProviderDefaults.googleKeychainAccount)
        }
    }

    /// When `false`, plan generation skips `/api/generate-plan` after on-device/PCC failure. Defaults to `true`.
    static var planCloudFallbackEnabled: Bool {
        get {
            UserDefaults.standard.object(forKey: MangoxCoachLanguageModelProviderDefaults.planCloudFallbackKey) as? Bool
                ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: MangoxCoachLanguageModelProviderDefaults.planCloudFallbackKey)
        }
    }

    /// Builds a coach session on a third-party `LanguageModel` when the vendor SPM package is linked.
    @available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
    static func makeThirdPartyCoachSession(
        planIntake: Bool,
        tools: [any Tool],
        history: [Transcript.Entry] = []
    ) -> LanguageModelSession? {
        guard isThirdPartyFallbackConfigured else { return nil }
        let instructions = CoachDynamicProfiles.pccCoachInstructions(planIntake: planIntake)

        #if canImport(AnthropicFoundationModels)
        if selectedProvider == .anthropic, let key = apiKey(for: .anthropic), !key.isEmpty {
            let model = AnthropicLanguageModel(apiKey: key)
            return LanguageModelSession(
                model: model,
                tools: tools,
                instructions: Instructions(instructions),
                history: history
            )
        }
        #endif

        #if canImport(GoogleGenerativeAIFoundationModels)
        if selectedProvider == .google, let key = apiKey(for: .google), !key.isEmpty {
            let model = GoogleGenerativeAILanguageModel(apiKey: key)
            return LanguageModelSession(
                model: model,
                tools: tools,
                instructions: Instructions(instructions),
                history: history
            )
        }
        #endif

        return nil
    }
}

// MARK: - Keychain

private enum MangoxCoachProviderKeychain {
    static func save(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: "com.abchalita.Mangox.coach.providers",
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: "com.abchalita.Mangox.coach.providers",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
            let data = item as? Data,
            let value = String(data: data, encoding: .utf8)
        else { return nil }
        return value
    }

    static func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: "com.abchalita.Mangox.coach.providers",
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw URLError(.cannotWriteToFile)
        }
    }
}
