import Foundation
import os.log
import Supabase

private let externalWebhookLogger = Logger(subsystem: "com.abchalita.Mangox", category: "ExternalWebhooks")

/// Consumes server-routed Strava/WHOOP webhook events when the app is foregrounded.
@MainActor
final class ExternalWebhookSignalService {
    private let userId: () -> UUID?
    private let whoopService: WhoopService
    private let syncExternalCyclingWorkouts: SyncExternalCyclingWorkoutsUseCase
    private var isConsuming = false

    init(
        userId: @escaping () -> UUID?,
        whoopService: WhoopService,
        syncExternalCyclingWorkouts: SyncExternalCyclingWorkoutsUseCase
    ) {
        self.userId = userId
        self.whoopService = whoopService
        self.syncExternalCyclingWorkouts = syncExternalCyclingWorkouts
    }

    func consumePendingSignals() async {
        guard !isConsuming, let userId = userId(), let client = MangoxSupabase.shared else { return }
        isConsuming = true
        defer { isConsuming = false }

        do {
            let rows: [Row] = try await client
                .from("external_webhook_events")
                .select("id,provider,event_type,processed_at,created_at")
                .eq("user_id", value: userId.uuidString)
                .order("created_at", ascending: false)
                .limit(50)
                .execute()
                .value

            let pending = rows.filter { $0.processed_at == nil }
            guard !pending.isEmpty else { return }

            if pending.contains(where: { $0.provider == LinkedOAuthProvider.whoop.rawValue }) {
                await whoopService.handleWebhookSignal()
            }

            if pending.contains(where: { $0.provider == LinkedOAuthProvider.strava.rawValue || $0.event_type.hasPrefix("workout.") }) {
                _ = try? await syncExternalCyclingWorkouts()
            }

            for row in pending {
                try await markProcessed(row.id, client: client)
            }
        } catch {
            let message = error.localizedDescription
            if message.contains("external_webhook_events"), message.contains("schema cache") {
                return
            }
            externalWebhookLogger.error("Webhook signal consume failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func markProcessed(_ id: UUID, client: SupabaseClient) async throws {
        try await client
            .from("external_webhook_events")
            .update(ProcessedAtPatch(processed_at: Date()))
            .eq("id", value: id.uuidString)
            .execute()
    }

    private struct Row: Decodable, Sendable {
        let id: UUID
        let provider: String
        let event_type: String
        let processed_at: Date?
        let created_at: Date
    }

    private struct ProcessedAtPatch: Encodable, Sendable {
        let processed_at: Date
    }
}
