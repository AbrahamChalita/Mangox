// Features/Profile/Data/DataSources/WhoopService+Workouts.swift
import Foundation

// MARK: - DTOs

struct WhoopWorkoutPage: Decodable, Sendable {
    let records: [WhoopWorkoutDTO]
    let next_token: String?
}

struct WhoopWorkoutDTO: Decodable, Sendable {
    let id: String
    let start: String
    let end: String?
    let sport_id: Int
    let sport_name: String
    let score_state: String?
    let score: Score?

    struct Score: Decodable, Sendable {
        let strain: Double?
        let average_heart_rate: Int?
        let max_heart_rate: Int?
        let kilojoule: Double?
        let distance_meter: Double?
        let altitude_gain_meter: Double?
        let altitude_change_meter: Double?
        let percent_recorded: Double?
        let zone_durations: ZoneDurations?

        struct ZoneDurations: Decodable, Sendable {
            let zone_zero_milli: Int?
            let zone_one_milli: Int?
            let zone_two_milli: Int?
            let zone_three_milli: Int?
            let zone_four_milli: Int?
            let zone_five_milli: Int?
        }
    }
}

// MARK: - Fetch extension

extension WhoopService {
    func fetchRecentWorkouts(since: Date, until: Date) async throws -> [WhoopWorkoutDTO] {
        guard isConnected else { return [] }

        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var all: [WhoopWorkoutDTO] = []
        var nextToken: String? = nil
        let cap = 200

        repeat {
            var items: [URLQueryItem] = [
                URLQueryItem(name: "start", value: fmt.string(from: since)),
                URLQueryItem(name: "end", value: fmt.string(from: until)),
                URLQueryItem(name: "limit", value: "25"),
            ]
            if let token = nextToken {
                items.append(URLQueryItem(name: "nextToken", value: token))
            }

            let page: WhoopWorkoutPage = try await authorizedGet(
                path: "/v2/activity/workout",
                queryItems: items,
                context: "WHOOP workouts"
            )
            all.append(contentsOf: page.records)
            nextToken = page.next_token
        } while nextToken != nil && all.count < cap

        return all
    }
}
