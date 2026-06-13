import XCTest
@testable import Mangox

@MainActor
final class PlanIntakeLocalDraftStagingTests: XCTestCase {
    func testDraftWhenUserRequestsGenerationAndTranscriptHasMinimumFields() {
        let messages: [ChatMessage] = [
            .user("Build a training plan for Gran Fondo Stelvio"),
            .user("The race is on 2026-09-12 with about 8 hours per week, intermediate."),
            .user("Yes, generate my plan now"),
            ChatMessage(
                id: UUID(),
                role: .assistant,
                content: "Great — I have everything I need. Ready to generate your plan.",
                timestamp: .now,
                suggestedActions: [],
                followUpQuestion: nil,
                followUpBlocks: [],
                thinkingSteps: [],
                category: "plan_intake",
                tags: ["plan"],
                references: [],
                usedWebSearch: false,
                feedbackScore: nil,
                confidence: 1.0,
                imageJPEG: nil
            ),
        ]

        let turn = PlanIntakeLocalDraftStaging.TurnContext(
            body: messages.last!.content,
            followUp: "",
            suggestedActionLabels: [],
            category: "plan_intake",
            followUpBlocksCount: 0
        )

        let draft = PlanIntakeLocalDraftStaging.draftIfReady(messages: messages, turn: turn, ftp: 250)
        XCTAssertNotNil(draft)
        XCTAssertEqual(draft?.inputs.event_date, "2026-09-12")
        XCTAssertEqual(draft?.inputs.weekly_hours, 8)
        XCTAssertEqual(draft?.inputs.experience, "intermediate")
    }

    func testNoDraftWhileFollowUpQuestionRemains() {
        let messages: [ChatMessage] = [
            .user("Build a training plan for Paris-Roubaix on 2026-04-12"),
        ]
        let turn = PlanIntakeLocalDraftStaging.TurnContext(
            body: "How many hours can you train per week?",
            followUp: "How many hours can you train per week?",
            suggestedActionLabels: ["6 hours", "8 hours"],
            category: "plan_intake",
            followUpBlocksCount: 0
        )

        XCTAssertNil(PlanIntakeLocalDraftStaging.draftIfReady(messages: messages, turn: turn, ftp: 250))
    }
}
