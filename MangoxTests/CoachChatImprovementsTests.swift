import Foundation
import SwiftUI
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
                "Search the web for latest polarized training study",
                isPro: false,
                forcePlanIntake: false
            )
        )
    }

    @Test func deliveryPathFromMessageCategory_mapsThirdParty() {
        #expect(
            CoachDeliveryPath.fromMessageCategory("third_party_coach") == .thirdPartyLanguageModel
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

    @Test func metricHighlighting_findsMetricsAndIgnoresBold() {
        let raw = "My threshold power is **250 W** but my target FTP is 275W and max HR is 190 bpm."
        
        let formatted = CoachAssistantFormatting.attributedContentForStreaming(from: raw, highlightMetrics: true)
        let plain = String(formatted.characters)
        #expect(plain == "My threshold power is 250 W but my target FTP is 275W and max HR is 190 bpm.")
        
        if let range275 = plain.range(of: "275W"),
           let range190 = plain.range(of: "190 bpm"),
           let range250 = plain.range(of: "250 W") {
            
            let offset275 = plain.distance(from: plain.startIndex, to: range275.lowerBound)
            let offset190 = plain.distance(from: plain.startIndex, to: range190.lowerBound)
            let offset250 = plain.distance(from: plain.startIndex, to: range250.lowerBound)
            
            let idx275 = formatted.characters.index(formatted.startIndex, offsetBy: offset275)
            let idx190 = formatted.characters.index(formatted.startIndex, offsetBy: offset190)
            let idx250 = formatted.characters.index(formatted.startIndex, offsetBy: offset250)

            #expect(metricHighlightAttributes(at: idx275, in: formatted).hasOrangeHighlight)
            #expect(metricHighlightAttributes(at: idx190, in: formatted).hasOrangeHighlight)
            #expect(!metricHighlightAttributes(at: idx250, in: formatted).hasOrangeHighlight)
            #expect(metricHighlightAttributes(at: idx250, in: formatted).isBoldOnly)
        } else {
            Issue.record("Failed to find metric substrings in output")
        }
    }
}

private struct MetricHighlightAttributes {
    var hasOrangeHighlight: Bool
    var isBoldOnly: Bool
}

private func metricHighlightAttributes(
    at index: AttributedString.Index,
    in text: AttributedString
) -> MetricHighlightAttributes {
    for run in text.runs where run.range.contains(index) {
        let emphasized = run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true
        return MetricHighlightAttributes(
            hasOrangeHighlight: run.foregroundColor != nil && emphasized,
            isBoldOnly: run.foregroundColor == nil && emphasized
        )
    }
    return MetricHighlightAttributes(hasOrangeHighlight: false, isBoldOnly: false)
}

private extension AIService {
    static let dateFormatterForTests: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt
    }()
}
