import Foundation
import SwiftData

@Model
final class AIGeneratedPlan {
    @Attribute(.unique) var id: String
    var planJSON: Data
    var generatedAt: Date
    var userPrompt: String
    /// Encoded `PlanInputs` for “Regenerate similar” (nil for plans created before this field existed).
    var regenerationInputsJSON: Data?

    init(
        id: String = UUID().uuidString,
        planJSON: Data,
        generatedAt: Date = .now,
        userPrompt: String,
        regenerationInputsJSON: Data? = nil
    ) {
        self.id = id
        self.planJSON = planJSON
        self.generatedAt = generatedAt
        self.userPrompt = userPrompt
        self.regenerationInputsJSON = regenerationInputsJSON
    }

    var plan: TrainingPlan? {
        TrainingPlan.decodeFromStoredJSON(planJSON)
    }
}
