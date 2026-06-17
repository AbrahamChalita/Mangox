import Foundation
import Testing
@testable import Mangox

struct StravaServiceTests {

    @Test func apiBaseHostIsStravaV3() {
        #expect(StravaService.apiBase.host == "www.api-v3.strava.com")
    }
}
