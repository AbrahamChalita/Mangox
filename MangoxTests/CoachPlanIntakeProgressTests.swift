import XCTest
@testable import Mangox

@MainActor
final class CoachPlanIntakeProgressTests: XCTestCase {
    func testSnapshotForEventDateQuestion() {
        let message = ChatMessage(
            id: UUID(),
            role: .assistant,
            content: "Let's build your training plan.",
            timestamp: .now,
            suggestedActions: [],
            followUpQuestion: "What is your target race date?",
            followUpBlocks: [],
            thinkingSteps: [],
            category: "clarification",
            tags: [],
            references: [],
            usedWebSearch: false,
            feedbackScore: nil,
            confidence: 1
        )

        let snapshot = CoachPlanIntakeProgress.snapshot(for: message)
        XCTAssertEqual(snapshot?.step, 2)
        XCTAssertEqual(snapshot?.fieldLabel, "Event date")
    }

    func testTimestampGapThreshold() {
        let earlier = ChatMessage.user("Hi")
        let later = ChatMessage(
            id: UUID(),
            role: .user,
            content: "Follow up",
            timestamp: earlier.timestamp.addingTimeInterval(400),
            suggestedActions: [],
            followUpQuestion: nil,
            followUpBlocks: [],
            thinkingSteps: [],
            category: nil,
            tags: [],
            references: [],
            usedWebSearch: false,
            feedbackScore: nil,
            confidence: 1
        )

        XCTAssertTrue(CoachMessageTimestampFormatting.shouldShow(before: earlier, current: later))
    }
}
