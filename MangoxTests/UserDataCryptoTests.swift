import CryptoKit
import Foundation
import Testing
@testable import Mangox

@MainActor
struct UserDataCryptoTests {
    @Test func roundTripMatchesWireFormat() throws {
        guard UserDataCrypto.isConfigured else { return }

        let payload = Data("strava-session-test".utf8)
        let encrypted = try UserDataCrypto.encrypt(payload)
        let decrypted = try UserDataCrypto.decrypt(encrypted)
        #expect(decrypted == payload)
    }
}
