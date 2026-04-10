// Features/Workout/Data/PersistenceModels/WorkoutRAGChunk.swift
import Foundation
import SwiftData

/// One embeddable row per completed workout for on-device semantic retrieval (coach RAG).
@Model
final class WorkoutRAGChunk {
    var id: UUID
    /// Source workout; at most one chunk per workout.
    @Attribute(.unique) var workoutID: UUID
    var startDate: Date
    /// Fingerprint of source fields used to skip redundant re-embedding.
    var contentSignature: UInt64
    /// `NLEmbedding.currentSentenceEmbeddingRevision(for:)` when embedded.
    var embeddingModelRevision: Int
    /// Plaintext injected into coach prompts when this chunk ranks highly.
    var chunkText: String
    /// Float32 little-endian vector from `NLEmbedding.vector(for:)` (same dimensionality as the active sentence model).
    var embeddingData: Data

    init(
        workoutID: UUID,
        startDate: Date,
        contentSignature: UInt64,
        embeddingModelRevision: Int,
        chunkText: String,
        embeddingData: Data
    ) {
        self.id = UUID()
        self.workoutID = workoutID
        self.startDate = startDate
        self.contentSignature = contentSignature
        self.embeddingModelRevision = embeddingModelRevision
        self.chunkText = chunkText
        self.embeddingData = embeddingData
    }
}
