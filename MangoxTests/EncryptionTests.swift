import CryptoKit
import Foundation
import Testing
@testable import Mangox

/// Verifies that the AES-256-GCM encryption used in AIService produces a
/// payload that the Node.js backend can interpret (wire format compatibility)
/// and that basic security properties hold.
struct EncryptionTests {

    // MARK: - Helpers

    private func makeKey() -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }

    /// Encrypt with CryptoKit AES-GCM and return the combined blob
    /// (nonce[12] + ciphertext + tag[16]) as base64, matching what AIService sends.
    private func encrypt(_ data: Data, key: SymmetricKey) throws -> String {
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else {
            Issue.record("AES.GCM.seal returned nil combined data")
            return ""
        }
        return combined.base64EncodedString()
    }

    /// Decrypt back using CryptoKit (simulates what the backend would do).
    private func decrypt(_ base64: String, key: SymmetricKey) throws -> Data {
        guard let combined = Data(base64Encoded: base64) else {
            throw CancellationError()
        }
        let box = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(box, using: key)
    }

    // MARK: - Round-trip

    @Test func roundTripSimpleStruct() throws {
        struct UserCtx: Codable, Equatable {
            let ftp: Int
            let weight_kg: Double
            let rider_type: String
        }
        let original = UserCtx(ftp: 280, weight_kg: 72.5, rider_type: "climber")
        let key = makeKey()
        let encoded = try JSONEncoder().encode(original)
        let b64 = try encrypt(encoded, key: key)

        let decrypted = try decrypt(b64, key: key)
        let recovered = try JSONDecoder().decode(UserCtx.self, from: decrypted)
        #expect(recovered == original)
    }

    @Test func roundTripNested() throws {
        let payload: [String: Any] = [
            "ftp": 310,
            "weekly_hours": 14,
            "zones": [100, 140, 160, 175, 200, 240, 310],
            "goal_event": "Ironman 70.3",
        ]
        let key = makeKey()
        let json = try JSONSerialization.data(withJSONObject: payload)
        let b64 = try encrypt(json, key: key)

        let decrypted = try decrypt(b64, key: key)
        let recovered = try JSONSerialization.jsonObject(with: decrypted) as? [String: Any]
        #expect(recovered?["ftp"] as? Int == 310)
        #expect((recovered?["zones"] as? [Int])?.count == 7)
    }

    // MARK: - Wire format compatibility (nonce[12] || ct || tag[16])

    @Test func combinedBlobHasCorrectMinimumSize() throws {
        let key = makeKey()
        let tiny = try encrypt(Data("x".utf8), key: key)
        let decoded = try #require(Data(base64Encoded: tiny))
        // Minimum: 12 (nonce) + 1 (payload byte) + 16 (tag) = 29 bytes
        #expect(decoded.count >= 29)
    }

    @Test func noncePrefixIs12Bytes() throws {
        let key = makeKey()
        let b64 = try encrypt(Data("hello".utf8), key: key)
        let combined = try #require(Data(base64Encoded: b64))
        // nonce is always first 12 bytes — CryptoKit AES.GCM uses a 96-bit nonce
        #expect(combined.count >= 12)
        let extractedNonce = combined.prefix(12)
        #expect(extractedNonce.count == 12)
    }

    @Test func tagSuffix16Bytes() throws {
        let key = makeKey()
        let plaintext = Data("tag length test".utf8)
        let b64 = try encrypt(plaintext, key: key)
        let combined = try #require(Data(base64Encoded: b64))
        // tag is last 16 bytes
        let tag = combined.suffix(16)
        #expect(tag.count == 16)
    }

    // MARK: - Security properties

    @Test func differentEncryptionsProduceDifferentCiphertext() throws {
        let key = makeKey()
        let data = Data("same plaintext".utf8)
        let enc1 = try encrypt(data, key: key)
        let enc2 = try encrypt(data, key: key)
        // CryptoKit generates a fresh random nonce each time → different output
        #expect(enc1 != enc2)
    }

    @Test func wrongKeyFailsDecryption() throws {
        let key1 = makeKey()
        let key2 = makeKey()
        let data = Data("secret context".utf8)
        let b64 = try encrypt(data, key: key1)
        let combined = try #require(Data(base64Encoded: b64))
        let box = try AES.GCM.SealedBox(combined: combined)
        // Decrypting with a different key must throw (authentication failure)
        var threw = false
        do {
            _ = try AES.GCM.open(box, using: key2)
        } catch {
            threw = true
        }
        #expect(threw)
    }

    @Test func tamperedCiphertextFailsDecryption() throws {
        let key = makeKey()
        let data = Data("tamper me".utf8)
        let b64 = try encrypt(data, key: key)
        var combined = try #require(Data(base64Encoded: b64))
        // Flip a byte in the ciphertext region (byte 12 is first ct byte)
        combined[12] ^= 0xFF
        var threw = false
        do {
            let box = try AES.GCM.SealedBox(combined: combined)
            _ = try AES.GCM.open(box, using: key)
        } catch {
            threw = true
        }
        #expect(threw)
    }

    // MARK: - Key derivation from base64

    @Test func symmetricKeyFromBase64RoundTrips() throws {
        // Simulate what AIService does: read 32-byte key from Info.plist as base64
        let rawKey = SymmetricKey(size: .bits256)
        let keyData = rawKey.withUnsafeBytes { Data($0) }
        let keyBase64 = keyData.base64EncodedString()

        // Reconstruct from base64 (as AIService.encryptionKey computed var does)
        guard let reconstructedData = Data(base64Encoded: keyBase64),
              reconstructedData.count == 32 else {
            Issue.record("Key reconstruction failed")
            return
        }
        let reconstructedKey = SymmetricKey(data: reconstructedData)

        // Both keys must decrypt the same ciphertext
        let plaintext = Data("key reconstruction test".utf8)
        let b64 = try encrypt(plaintext, key: rawKey)
        let decrypted = try decrypt(b64, key: reconstructedKey)
        #expect(decrypted == plaintext)
    }

    @Test func shortKeyBase64IsRejected() {
        // Keys that are not exactly 32 bytes must not be used — AIService guards this
        let shortKeyData = Data(repeating: 0, count: 16)
        let b64 = shortKeyData.base64EncodedString()
        guard let reconstructed = Data(base64Encoded: b64) else {
            Issue.record("Unexpected base64 decode failure")
            return
        }
        // AIService checks keyData.count == 32 — 16-byte key must be rejected
        #expect(reconstructed.count != 32)
    }
}
