import Testing
@testable import Mangox

@MainActor
@Suite struct OnDeviceCoachRoutingTests {
    @Test func heuristicCloudRouteCatchesPlanIntents() {
        #expect(OnDeviceCoachEngine.heuristicCloudRoute(for: "Build me a training plan for my event"))
        #expect(OnDeviceCoachEngine.heuristicCloudRoute(for: String(repeating: "x", count: 900)))
    }

    @Test func heuristicLocalPreferredCatchesStatsQuestions() {
        #expect(OnDeviceCoachEngine.heuristicLocalPreferred(for: "What is my FTP?"))
        #expect(OnDeviceCoachEngine.heuristicLocalPreferred(for: "How tired am I this week?"))
    }

    @Test func passesOnDeviceNarrowHeuristicsRejectsPlanKeywords() {
        #expect(!OnDeviceCoachEngine.passesOnDeviceNarrowHeuristics(for: "Generate a plan for June"))
        #expect(OnDeviceCoachEngine.heuristicPrefersPCCCoach(for: "Generate a plan for June"))
    }

    @Test func passesOnDeviceNarrowHeuristicsAllowsShortLocalQuestions() {
        #expect(OnDeviceCoachEngine.passesOnDeviceNarrowHeuristics(for: "What's my TSS?"))
        #expect(OnDeviceCoachEngine.passesOnDeviceNarrowHeuristics(for: "Hi"))
    }

    @Test func webSearchSkipsNarrowAndPrefersPCC() {
        #expect(!OnDeviceCoachEngine.passesOnDeviceNarrowHeuristics(for: "Search the web for polarized training"))
        #expect(OnDeviceCoachEngine.heuristicPrefersPCCWebSearch(for: "Search the web for polarized training"))
    }

    @Test func conversationalSearchIntentRoutesToWeb() {
        let message = "can you search, what is the next cycling event in mexico city?"
        #expect(OnDeviceCoachEngine.heuristicPrefersPCCWebSearch(for: message))
        #expect(!OnDeviceCoachEngine.passesOnDeviceNarrowHeuristics(for: message))
    }
}
