import XCTest
@testable import Mangox

final class MangoxSSEFallbackPolicyTests: XCTestCase {
    func testAllowsFallbackBeforeStreamOutput() {
        XCTAssertTrue(MangoxSSEFallbackPolicy.shouldFallbackToNonStreaming(receivedStreamPayload: false))
    }

    func testBlocksFallbackAfterStreamOutput() {
        XCTAssertFalse(MangoxSSEFallbackPolicy.shouldFallbackToNonStreaming(receivedStreamPayload: true))
    }
}
