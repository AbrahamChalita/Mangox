import Testing
@testable import Mangox

struct PrecisionCoachOutcomeStoreTests {
    @Test func recordAndLoad_persistsEvents() {
        PrecisionCoachOutcomeStore.clearAll()
        defer { PrecisionCoachOutcomeStore.clearAll() }

        PrecisionCoachOutcomeStore.record(
            .init(kind: .planStarted, planID: "plan-a", source: "test")
        )
        PrecisionCoachOutcomeStore.record(
            .init(kind: .planDayCompleted, planID: "plan-a", dayID: "d1", source: "indoor_auto")
        )

        let events = PrecisionCoachOutcomeStore.load()
        #expect(events.count == 2)
        #expect(events[0].kind == .planStarted)
        #expect(events[1].kind == .planDayCompleted)
        #expect(PrecisionCoachOutcomeStore.events(forPlanID: "plan-a").count == 2)
    }
}
