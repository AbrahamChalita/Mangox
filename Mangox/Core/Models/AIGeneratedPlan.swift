import Foundation
import SwiftData

@Model
final class AIGeneratedPlan {
    @Attribute(.unique) var id: String
    var planJSON: Data
    var generatedAt: Date
    var userPrompt: String

    init(
        id: String = UUID().uuidString,
        planJSON: Data,
        generatedAt: Date = .now,
        userPrompt: String
    ) {
        self.id = id
        self.planJSON = planJSON
        self.generatedAt = generatedAt
        self.userPrompt = userPrompt
    }

    var plan: TrainingPlan? {
        TrainingPlan.decodeFromStoredJSON(planJSON)
    }
}
