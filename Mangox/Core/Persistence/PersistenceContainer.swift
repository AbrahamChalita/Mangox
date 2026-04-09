// Core/Persistence/PersistenceContainer.swift
import Foundation
import SwiftData

/// Assembles the SwiftData ModelContainer for the app.
/// All @Model types must be registered here — this is the single source of truth.
enum PersistenceContainer {

    /// Production container. Crashes at launch if the schema is invalid (fatal misconfiguration).
    static let shared: ModelContainer = {
        do {
            return try makeContainer(inMemory: false)
        } catch {
            fatalError("Failed to create SwiftData ModelContainer: \(error)")
        }
    }()

    /// Creates a container optionally in-memory (for previews and tests).
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
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
            TrainingPlanProgress.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
