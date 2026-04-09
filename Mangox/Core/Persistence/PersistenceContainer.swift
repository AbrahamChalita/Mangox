// Core/Persistence/PersistenceContainer.swift
import Foundation
import SwiftData

/// Assembles the SwiftData ModelContainer for the app.
/// All @Model types must be registered here.
enum PersistenceContainer {
    static func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Workout.self,
            WorkoutSample.self,
            LapSplit.self,
            WorkoutRAGChunk.self,
            CustomWorkoutTemplate.self,
            ChatSession.self,
            CoachChatMessage.self,
            AIGeneratedPlan.self,
            FitnessSettingsSnapshot.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
