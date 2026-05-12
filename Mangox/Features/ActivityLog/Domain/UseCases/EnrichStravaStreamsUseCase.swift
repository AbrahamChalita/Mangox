// Features/ActivityLog/Domain/UseCases/EnrichStravaStreamsUseCase.swift
import Foundation

/// Lazily enriches Strava-imported activities with stream-derived metrics
/// (best-km split, HR-zone distribution). Bulk imports skip these to stay
/// within Strava's 15-minute rate budget; this runs on demand when the UI
/// actually needs the richer data — e.g. when opening a DaySummaryStudio.
@MainActor
struct EnrichStravaStreamsUseCase {
    let stravaService: StravaService
    let repository: LoggedActivityRepository

    struct Result: Sendable {
        let updated: Int
        let skipped: Int
        let rateLimited: Bool
    }

    /// Returns true when an activity is a Strava import that's missing stream-derived metrics
    /// and would benefit from a streams call. Used as the dedupe gate so we never refetch.
    static func needsEnrichment(_ activity: LoggedActivity) -> Bool {
        guard activity.source == .strava, activity.externalID != nil else { return false }
        let m = activity.metrics
        // Distance sports want best-km split; if it's already populated, no work.
        if activity.type.isCardioDistance && m.bestKmSplitSeconds != nil {
            return false
        }
        // For non-distance sports the only stream payoff is HR zones; bail if already present.
        if !activity.type.isCardioDistance && m.heartRateZoneMillis != nil {
            return false
        }
        // No point fetching streams for a 5-minute walk that won't have a meaningful km split.
        if activity.type.isCardioDistance && (m.distanceMeters ?? 0) < 1000 {
            return false
        }
        return true
    }

    /// Enriches each candidate activity in series (parallelism would just batch into the rate
    /// limit anyway). Returns a per-activity callback so callers can refresh their UI as
    /// metrics become available, instead of waiting for the entire batch.
    func enrich(
        _ activities: [LoggedActivity],
        onProgress: ((LoggedActivity) -> Void)? = nil
    ) async -> Result {
        let candidates = activities.filter(Self.needsEnrichment)
        guard !candidates.isEmpty else {
            return .init(updated: 0, skipped: activities.count, rateLimited: false)
        }
        guard stravaService.isConnected else {
            return .init(updated: 0, skipped: activities.count, rateLimited: false)
        }

        var updated = 0
        var rateLimited = false

        for activity in candidates {
            if stravaService.isRateLimitTight {
                rateLimited = true
                break
            }
            guard let externalID = activity.externalID, let stravaID = Int(externalID) else { continue }

            let streams: StravaService.ActivityStreams?
            do {
                streams = try await stravaService.fetchActivityStreams(id: stravaID)
            } catch {
                continue
            }
            guard let streams else { continue }

            var metrics = activity.metrics
            if activity.type.isCardioDistance, metrics.bestKmSplitSeconds == nil,
               let bestKm = StravaActivityMapper.bestKmSplitSeconds(streams: streams) {
                metrics.bestKmSplitSeconds = bestKm
            }
            if metrics.heartRateZoneMillis == nil,
               let zones = StravaActivityMapper.heartRateZoneMillis(
                streams: streams,
                maxHR: Double(HeartRateZone.maxHR)
               ) {
                metrics.heartRateZoneMillis = zones
            }

            // Persist via the existing update path. Reuse all immutable fields off the loaded activity.
            let draft = LoggedActivityDraft(
                id: activity.id,
                source: activity.source,
                externalID: activity.externalID,
                type: activity.type,
                customLabel: activity.customLabel,
                startDate: activity.startDate,
                durationSeconds: activity.durationSeconds,
                intensity: activity.intensity,
                rpe: activity.rpe,
                notes: activity.notes,
                metrics: metrics
            )
            if let saved = try? repository.update(draft) {
                updated += 1
                onProgress?(saved)
            }
        }

        let skipped = activities.count - updated
        return .init(updated: updated, skipped: skipped, rateLimited: rateLimited)
    }
}
