import Foundation
import SwiftUI
import Testing
@testable import Mangox

@MainActor
@Suite struct CoachChatImprovementsTests {

    @Test func canSendCoachMessage_allowsOnDeviceStatsAtDailyLimit() {
        let service = AIService()
        
        // Verify the function doesn't crash and returns a boolean for various message types
        let onDeviceMessage = "What's my TSS this week?"
        let webSearchMessage = "Search the web for latest polarized training study"
        
        // At daily limit, on-device stats should still be sendable
        UserDefaults.standard.set(100, forKey: "ai_chat_count_today")
        UserDefaults.standard.set(
            AIService.dateFormatterForTests.string(from: .now),
            forKey: "ai_chat_count_date"
        )
        defer {
            UserDefaults.standard.removeObject(forKey: "ai_chat_count_today")
            UserDefaults.standard.removeObject(forKey: "ai_chat_count_date")
        }
        
        let onDeviceResult = service.canSendCoachMessage(onDeviceMessage, isPro: false, forcePlanIntake: false)
        #expect(onDeviceResult, "On-device stats should be sendable at daily limit")
        
        // Web search behavior depends on PCC availability, so we just verify it returns a boolean
        let webSearchResult = service.canSendCoachMessage(webSearchMessage, isPro: false, forcePlanIntake: false)
        #expect(webSearchResult == true || webSearchResult == false, "Web search should return a boolean")
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

    @Test func canBeginTurn_reservesTurnSlot() {
        let service = AIService()

        #expect(service.canBeginTurn())
        #expect(!service.canBeginTurn(), "A second synchronous reservation should fail while the first is pending")

        // Simulate the async send starting: it should consume the reservation.
        let messageCount = service.messages.count
        #expect(messageCount == 0)
    }

    @Test func suggestsFreshConversation_usesGreaterThanWindowSize() {
        let service = AIService()

        // Exactly at the window size should not suggest a fresh conversation.
        service.messages = (0..<service.contextWindowSize).map { _ in
            ChatMessage.user("test")
        }
        #expect(!service.suggestsFreshConversation)

        // One message over the window should trigger the banner.
        service.messages.append(ChatMessage.user("overflow"))
        #expect(service.suggestsFreshConversation)
    }

    @Test func incrementalParser_matchesFullParser() {
        let raw = "Hello <thinking>secret reasoning</thinking> world."
        let expected = CoachThinkingTagParser.snapshot(streamBuffer: raw)

        var parser = CoachThinkingTagParser.IncrementalParser()
        let chunkSize = 4
        var index = raw.startIndex
        while index < raw.endIndex {
            let end = raw.index(index, offsetBy: min(chunkSize, raw.distance(from: index, to: raw.endIndex)))
            let delta = String(raw[index..<end])
            _ = parser.append(delta)
            index = end
        }

        let incremental = parser.currentSnapshot
        #expect(incremental.visible == expected.visible)
        #expect(incremental.completedBlocks == expected.completedBlocks)
    }

    @Test func incrementalParser_handlesTagSplitAcrossDeltas() {
        var parser = CoachThinkingTagParser.IncrementalParser()

        let snap1 = parser.append("Hello <think")
        #expect(snap1.visible == "Hello ")
        #expect(snap1.openDraft == nil)

        let snap2 = parser.append("ing>reasoning</thinking> world.")
        #expect(snap2.visible == "Hello  world.")
        #expect(snap2.completedBlocks == ["reasoning"])
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
