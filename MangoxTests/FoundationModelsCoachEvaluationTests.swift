import Testing
@testable import Mangox

@MainActor
@Suite struct FoundationModelsCoachEvaluationTests {

    @Test func routingFixturesMatchSimulatedPaths() {
        for fixture in FoundationModelsCoachEvaluation.routingFixtures {
            let path = FoundationModelsCoachEvaluation.simulatedDeliveryPath(
                userMessage: fixture.message,
                planIntake: false,
                pccAvailable: true
            )
            if fixture.expectOnDevice {
                #expect(path == .onDeviceNarrow, "fixture \(fixture.name)")
            } else if fixture.expectPCC {
                #expect(path == .privateCloudCompute, "fixture \(fixture.name)")
            } else if fixture.expectCloudBackend {
                #expect(path == .mangoxCloudBackend, "fixture \(fixture.name)")
            }
        }
    }

    @Test func validateNarrowReplyRejectsInvalidNewlines() {
        let bad = NarrowCoachReply(
            reasoning: "plan",
            body: "Line one\nLine two",
            followUp: "",
            suggestedActions: [],
            tags: [],
            category: "training_advice"
        )
        #expect(FoundationModelsCoachEvaluation.validateNarrowReply(bad) != nil)
    }

    @Test func validateNarrowReplyAcceptsBulletLists() {
        let bullets = NarrowCoachReply(
            reasoning: "plan",
            body: "- Hold **245W** for 20 min\n- Add 10 min cooldown",
            followUp: "",
            suggestedActions: [],
            tags: ["power"],
            category: "training_advice"
        )
        #expect(FoundationModelsCoachEvaluation.validateNarrowReply(bullets) == nil)
    }

    @Test func validateNarrowReplyAcceptsGoodReply() {
        let good = NarrowCoachReply(
            reasoning: "plan",
            body: "Your week TSS is 312 with moderate recovery — consider an easy spin tomorrow.",
            followUp: "",
            suggestedActions: [NarrowSuggestedAction(label: "Show PMC trend")],
            tags: ["tss", "recovery"],
            category: "training_advice"
        )
        #expect(FoundationModelsCoachEvaluation.validateNarrowReply(good) == nil)
    }

    @Test func validateWorkoutInsightBounds() {
        #expect(
            FoundationModelsCoachEvaluation.validateWorkoutInsight(
                headline: "Solid threshold",
                bullets: ["NP 198W", "TSS 68"],
                narrative: "You held zone 3 well."
            ) == nil
        )
        #expect(
            FoundationModelsCoachEvaluation.validateWorkoutInsight(
                headline: "",
                bullets: ["x"],
                narrative: nil
            ) != nil
        )
    }

    @Test func heuristicSplitSeparatesWebFromPlans() {
        #expect(OnDeviceCoachEngine.heuristicPrefersPCCWebSearch(for: "search the web for studies"))
        #expect(OnDeviceCoachEngine.heuristicPrefersPCCCoach(for: "Build me a training plan"))
        #expect(!OnDeviceCoachEngine.heuristicPrefersPCCWebSearch(for: "Build me a training plan"))
    }

    @Test func webSearchDeferralDetection() {
        #expect(
            CoachReplyMetadataSupport.isWebSearchDeferralOnly(
                "Let me search for upcoming cycling events in Mexico City."
            )
        )
        #expect(
            !CoachReplyMetadataSupport.isWebSearchDeferralOnly(
                "The Gran Fondo CDMX is on 14 September 2026. See https://example.com for details."
            )
        )
    }

    @Test func localSpotlightHeuristicDoesNotForceCloud() {
        #expect(OnDeviceCoachEngine.heuristicPrefersLocalSpotlightSearch(for: "Find my notes about base week"))
        #expect(!OnDeviceCoachEngine.heuristicPrefersPCCWebSearch(for: "Find my notes about base week"))
        #expect(OnDeviceCoachEngine.passesOnDeviceNarrowHeuristics(for: "Find my notes about base week"))
    }

    @Test func routingFixturesIncludeAmbiguousCoachingPrompts() {
        let names = Set(FoundationModelsCoachEvaluation.routingFixtures.map(\.name))
        #expect(names.contains("intervals_today"))
        #expect(names.contains("sweet_spot_vs_threshold"))
    }
}
