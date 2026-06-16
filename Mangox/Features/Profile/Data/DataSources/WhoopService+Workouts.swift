// Features/Profile/Data/DataSources/WhoopService+Workouts.swift
import Foundation

// MARK: - DTOs

struct WhoopWorkoutPage: Decodable, Sendable {
    let records: [WhoopWorkoutDTO]
    let nextToken: String?
}

struct WhoopWorkoutDTO: Decodable, Sendable {
    let id: String
    let start: String
    let end: String?
    let sportId: Int
    let sportName: String
    let scoreState: String?
    let score: Score?

    struct Score: Decodable, Sendable {
        let strain: Double?
        let averageHeartRate: Int?
        let maxHeartRate: Int?
        let kilojoule: Double?
        let distanceMeter: Double?
        let altitudeGainMeter: Double?
        let altitudeChangeMeter: Double?
        let percentRecorded: Double?
        let zoneDurations: ZoneDurations?

        struct ZoneDurations: Decodable, Sendable {
            let zoneZeroMilli: Int?
            let zoneOneMilli: Int?
            let zoneTwoMilli: Int?
            let zoneThreeMilli: Int?
            let zoneFourMilli: Int?
            let zoneFiveMilli: Int?
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
            nextToken = page.nextToken
        } while nextToken != nil && all.count < cap

        return all
    }
}
