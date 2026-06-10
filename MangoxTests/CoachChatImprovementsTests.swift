import Foundation
import Testing
@testable import Mangox

@MainActor
@Suite struct CoachChatImprovementsTests {

    @Test func canSendCoachMessage_allowsOnDeviceStatsAtDailyLimit() {
        let service = AIService()
        UserDefaults.standard.set(AIService.freeDailyLimit, forKey: "ai_chat_count_today")
        UserDefaults.standard.set(
            AIService.dateFormatterForTests.string(from: .now),
            forKey: "ai_chat_count_date"
        )
        defer {
            UserDefaults.standard.removeObject(forKey: "ai_chat_count_today")
            UserDefaults.standard.removeObject(forKey: "ai_chat_count_date")
        }

        #expect(
            service.canSendCoachMessage("What's my TSS this week?", isPro: false, forcePlanIntake: false)
        )
        #expect(
            !service.canSendCoachMessage(
                "Build me a training plan for my event",
                isPro: false,
                forcePlanIntake: false
            )
        )
    }

    @Test func deliveryPathFromMessageCategory_mapsOnDevice() {
        #expect(
            CoachDeliveryPath.fromMessageCategory("on_device") == .onDeviceNarrow
        )
        #expect(
            CoachDeliveryPath.fromMessageCategory("pcc_coach") == .privateCloudCompute
        )
    }

    @Test func precisionCoachRecordsCoachReplyEvent() {
        PrecisionCoachOutcomeStore.clearAll()
        defer { PrecisionCoachOutcomeStore.clearAll() }

        PrecisionCoachInstrumentation.coachReplyDelivered(
            path: CoachDeliveryPath.onDeviceNarrow.instrumentationLabel,
            category: "on_device",
            charCount: 120
        )

        let events = PrecisionCoachOutcomeStore.load()
        #expect(events.count == 1)
        #expect(events[0].kind == .coachReplyDelivered)
        #expect(events[0].source == CoachDeliveryPath.onDeviceNarrow.rawValue)
    }
}

private extension AIService {
    static let dateFormatterForTests: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt
    }()
}
