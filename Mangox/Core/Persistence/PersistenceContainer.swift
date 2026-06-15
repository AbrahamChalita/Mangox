// Core/Persistence/PersistenceContainer.swift
import Foundation
import SwiftData

/// Assembles the SwiftData ModelContainer for the app.
/// All @Model types must be registered here — this is the single source of truth.
enum PersistenceContainer {

    /// Production container. Crashes at launch if the schema is invalid (fatal misconfiguration).
    /// `nonisolated` so background tasks can create their own `ModelContext` without
    /// forcing every context build onto the main actor.
    nonisolated static let shared: ModelContainer = {
        do {
            return try makeContainer(inMemory: false)
        } catch {
            fatalError("Failed to create SwiftData ModelContainer: \(error)")
        }
    }()

    /// Creates a container optionally in-memory (for previews and tests).
    nonisolated static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
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
            LoggedActivityRecord.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
