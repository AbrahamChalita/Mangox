import CryptoKit
import Foundation

/// AES-256-GCM helpers for user-owned secrets at rest (coach context, linked OAuth tokens).
/// Uses `UserDataKey` from Info.plist (`USER_DATA_KEY` in xcconfig).
enum UserDataCrypto {
    static var isConfigured: Bool { symmetricKey != nil }

    private static var symmetricKey: SymmetricKey? {
        guard let b64 = Bundle.main.object(forInfoDictionaryKey: "UserDataKey") as? String,
              !b64.isEmpty,
              !b64.hasPrefix("$("),
              let keyData = Data(base64Encoded: b64),
              keyData.count == 32
        else { return nil }
        return SymmetricKey(data: keyData)
    }

    /// Encrypts bytes and returns base64(nonce ‖ ciphertext ‖ tag).
    static func encrypt(_ plaintext: Data) throws -> String {
        guard let key = symmetricKey else {
            throw CryptoError.keyNotConfigured
        }
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else {
            throw CryptoError.sealFailed
        }
        return combined.base64EncodedString()
    }

    static func decrypt(_ base64Ciphertext: String) throws -> Data {
        guard let key = symmetricKey else {
            throw CryptoError.keyNotConfigured
        }
        guard let combined = Data(base64Encoded: base64Ciphertext) else {
            throw CryptoError.invalidCiphertext
        }
        let box = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(box, using: key)
    }

    enum CryptoError: Error {
        case keyNotConfigured
        case sealFailed
        case invalidCiphertext
    }
}
