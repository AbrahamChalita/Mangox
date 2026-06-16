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

    @Test func whoopWorkoutPageDecodesWithSnakeCaseStrategy() throws {
        let json = """
        {
          "records": [
            {
              "id": "workout-1",
              "start": "2026-06-15T14:00:00.000Z",
              "end": "2026-06-15T15:00:00.000Z",
              "sport_id": 53,
              "sport_name": "Weightlifting",
              "score_state": "SCORED",
              "score": {
                "strain": 8.4,
                "average_heart_rate": 122,
                "max_heart_rate": 166,
                "kilojoule": 420,
                "distance_meter": 0,
                "altitude_gain_meter": 0,
                "altitude_change_meter": 0,
                "percent_recorded": 100,
                "zone_durations": {
                  "zone_zero_milli": 1000,
                  "zone_one_milli": 2000,
                  "zone_two_milli": 3000,
                  "zone_three_milli": 4000,
                  "zone_four_milli": 5000,
                  "zone_five_milli": 6000
                }
              }
            }
          ],
          "next_token": "next-page"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let page = try decoder.decode(WhoopWorkoutPage.self, from: json)

        #expect(page.nextToken == "next-page")
        #expect(page.records.first?.sportId == 53)
        #expect(page.records.first?.score?.averageHeartRate == 122)
        #expect(page.records.first?.score?.zoneDurations?.zoneFiveMilli == 6000)
    }
}
