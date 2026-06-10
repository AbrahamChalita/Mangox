import Foundation
import Testing
@testable import Mangox

@MainActor
struct WorkoutSyncPullTests {
    @Test func supabaseTemplateIntervalsDecode() throws {
        let json = """
        {
          "id": "de3a0d44-6502-4b1e-b308-6a2185d60670",
          "name": "Easy Recovery Ride - 60 Minutes",
          "intervals": [
            {
              "name": "Easy Pedaling",
              "zone": "Z1",
              "order": 1,
              "repeats": 1,
              "recoveryZone": "Z1",
              "durationSeconds": 300,
              "recoverySeconds": 0,
              "suggestedTrainerMode": "erg"
            }
          ],
          "created_at": "2026-06-09T06:21:50.1Z",
          "updated_at": "2026-06-09T06:21:50.1Z"
        }
        """.data(using: .utf8)!

        struct Row: Decodable {
            let id: UUID
            let name: String
            let intervals: [IntervalSegment]
            let created_at: Date
            let updated_at: Date
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let row = try decoder.decode(Row.self, from: json)
        #expect(row.name.contains("Recovery"))
        #expect(row.intervals.count == 1)
        #expect(row.intervals[0].zone == .z1)
        #expect(row.intervals[0].durationSeconds == 300)
    }
}
