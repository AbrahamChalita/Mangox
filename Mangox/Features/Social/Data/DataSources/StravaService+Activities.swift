// Features/Social/Data/DataSources/StravaService+Activities.swift
import Foundation

extension StravaService {
    /// Parse the rolling 15-min usage/limit pair off a Strava response. Strava sends both the
    /// 15-min and daily counters comma-separated; we only care about the first (15-min) bucket.
    func recordRateLimitHeaders(from response: URLResponse) {
        guard let http = response as? HTTPURLResponse else { return }
        let usage = http.value(forHTTPHeaderField: "X-RateLimit-Usage") ?? http.value(forHTTPHeaderField: "x-ratelimit-usage")
        let limit = http.value(forHTTPHeaderField: "X-RateLimit-Limit") ?? http.value(forHTTPHeaderField: "x-ratelimit-limit")
        guard let usage, let limit else { return }
        let usageShort = usage.split(separator: ",").first.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        let limitShort = limit.split(separator: ",").first.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        if let u = usageShort, let l = limitShort, l > 0 {
            updateRateLimitShortWindow(usage: u, limit: l)
        }
    }

    /// Per-second telemetry from a Strava activity. Strava returns these as parallel arrays — every stream
    /// has the same length and indexes line up across streams. We only decode the keys we ask for.
    struct ActivityStreams: Sendable {
        let time: [Int]
        let distance: [Double]
        let heartrate: [Int]
        let velocitySmooth: [Double]
        let cadence: [Int]
        let watts: [Int]
        let altitude: [Double]
        let temp: [Int]
    }

    private struct StreamSetResponse: Decodable {
        struct Stream: Decodable {
            let type: String?
            let data: [Double]?
        }
        let streams: [Stream]

        init(from decoder: Decoder) throws {
            // Strava returns either a top-level array (`/streams?keys=...`) or a keyed-by-type
            // dictionary (`?key_by_type=true`). Accept both.
            let container = try decoder.singleValueContainer()
            if let array = try? container.decode([Stream].self) {
                streams = array
                return
            }
            let dict = try container.decode([String: Stream].self)
            streams = dict.map { key, value in
                Stream(type: value.type ?? key, data: value.data)
            }
        }
    }

    /// Fetches non-cycling activities from Strava in the given window.
    /// Paginates until an empty page is returned.
    /// Strava `after` is exclusive — pass a date 1s before window start.
    /// `before` is exclusive too — pass end-of-day for a single-day window.
    func fetchRecentActivities(
        since: Date,
        before: Date? = nil,
        perPage: Int = 30
    ) async throws -> [SummaryActivity] {
        guard isConnected else { return [] }
        let token = try await validAccessToken()
        let afterEpoch = Int(since.timeIntervalSince1970)
        let beforeEpoch = before.map { Int($0.timeIntervalSince1970) }
        var page = 1
        var all: [SummaryActivity] = []

        while true {
            var components = URLComponents(url: Self.athleteActivitiesURL, resolvingAgainstBaseURL: false)
            var items: [URLQueryItem] = [
                URLQueryItem(name: "after", value: "\(afterEpoch)"),
                URLQueryItem(name: "per_page", value: "\(perPage)"),
                URLQueryItem(name: "page", value: "\(page)"),
            ]
            if let beforeEpoch {
                items.append(URLQueryItem(name: "before", value: "\(beforeEpoch)"))
            }
            components?.queryItems = items
            guard let url = components?.url else { break }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 20

            let (data, response) = try await urlSession.data(for: request)
            recordRateLimitHeaders(from: response)
            guard let http = response as? HTTPURLResponse else {
                throw StravaError.invalidResponse
            }
            guard (200..<300).contains(http.statusCode) else {
                let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
                throw StravaError.activityFetchFailed(message)
            }

            let batch = try JSONDecoder().decode([SummaryActivity].self, from: data)
            if batch.isEmpty { break }
            all.append(contentsOf: batch)
            if batch.count < perPage { break }
            page += 1
        }

        return all
    }

    func fetchActivityDetail(id: Int) async throws -> SummaryActivity {
        let token = try await validAccessToken()
        var components = URLComponents(
            url: Self.apiBase.appending(path: "activities/\(id)"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "include_all_efforts", value: "false")]
        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        let (data, response) = try await urlSession.data(for: request)
        recordRateLimitHeaders(from: response)
        guard let http = response as? HTTPURLResponse else {
            throw StravaError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw StravaError.activityFetchFailed(message)
        }
        return try JSONDecoder().decode(SummaryActivity.self, from: data)
    }

    /// Fetches per-second telemetry streams for an activity. Returns nil on failure or when the
    /// 15-minute rate budget is tight — callers should treat streams as optional enrichment.
    func fetchActivityStreams(id: Int) async throws -> ActivityStreams? {
        if isRateLimitTight { return nil }
        let token = try await validAccessToken()
        let keys = "time,distance,heartrate,velocity_smooth,cadence,watts,altitude,temp"
        var components = URLComponents(
            url: Self.apiBase.appending(path: "activities/\(id)/streams"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "keys", value: keys),
            URLQueryItem(name: "key_by_type", value: "true"),
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 25

        let (data, response) = try await urlSession.data(for: request)
        recordRateLimitHeaders(from: response)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }

        let parsed = try JSONDecoder().decode(StreamSetResponse.self, from: data)
        var byType: [String: [Double]] = [:]
        for s in parsed.streams {
            if let type = s.type, let data = s.data { byType[type] = data }
        }

        return ActivityStreams(
            time: (byType["time"] ?? []).map { Int($0) },
            distance: byType["distance"] ?? [],
            heartrate: (byType["heartrate"] ?? []).map { Int($0) },
            velocitySmooth: byType["velocity_smooth"] ?? [],
            cadence: (byType["cadence"] ?? []).map { Int($0) },
            watts: (byType["watts"] ?? []).map { Int($0) },
            altitude: byType["altitude"] ?? [],
            temp: (byType["temp"] ?? []).map { Int($0) }
        )
    }
}
