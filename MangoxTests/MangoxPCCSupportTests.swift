import XCTest
@testable import Mangox

@MainActor
final class MangoxPCCSupportTests: XCTestCase {
    func testSessionEstablishmentFailureDetectsOperationNotPermitted() {
        let error = NSError(
            domain: "ModelManager",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Operation not permitted"]
        )
        XCTAssertTrue(MangoxPCCSupport.isSessionEstablishmentFailure(error))
        XCTAssertTrue(MangoxPCCSupport.shouldFallbackToOnDeviceAfterPCCFailure(error))
    }

    func testQuotaErrorsAreNotSessionEstablishmentFailures() {
        let error = OnDevicePlanGeneratorError.quotaLimitReached("Daily limit reached.")
        XCTAssertFalse(MangoxPCCSupport.isSessionEstablishmentFailure(error))
        XCTAssertTrue(MangoxPCCSupport.isQuotaLimitReached(error))
    }

    func testPlanCloudFallbackDefaultsEnabled() {
        let key = MangoxCoachLanguageModelProviderDefaults.planCloudFallbackKey
        let defaults = UserDefaults.standard
        let prior = defaults.object(forKey: key)
        defer {
            if let prior {
                defaults.set(prior, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        defaults.removeObject(forKey: key)
        XCTAssertTrue(MangoxCoachLanguageModelProviderSupport.planCloudFallbackEnabled)
    }
}
