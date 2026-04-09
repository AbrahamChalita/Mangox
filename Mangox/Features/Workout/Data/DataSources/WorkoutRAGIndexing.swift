// Features/Workout/Data/DataSources/WorkoutRAGIndexing.swift
import Foundation
import NaturalLanguage
import SwiftData
import os.log

// MARK: - Vector math + encoding

private enum WorkoutRAGVectorCodec {
    static func encode(_ vector: [Double]) -> Data {
        let floats = vector.map { Float($0) }
        return floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    static func decodeToDouble(_ data: Data) -> [Double]? {
        guard !data.isEmpty, data.count % MemoryLayout<Float>.size == 0 else { return nil }
        let count = data.count / MemoryLayout<Float>.size
        return data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return nil }
            let ptr = base.assumingMemoryBound(to: Float.self)
            return (0..<count).map { Double(ptr[$0]) }
        }
    }

    static func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Float? {
        guard a.count == b.count, !a.isEmpty else { return nil }
        var dot: Double = 0
        var na: Double = 0
        var nb: Double = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        let denom = sqrt(na) * sqrt(nb)
        guard denom > 0 else { return nil }
        return Float(dot / denom)
    }
}

// MARK: - Chunk text + fingerprint

enum WorkoutRAGChunkBuilder {
    private static let logger = Logger(
        subsystem: "com.abchalita.Mangox", category: "WorkoutRAG")

    private static let fnvOffset: UInt64 = 0xcbf29ce484222325
    private static let fnvPrime: UInt64 = 0x100000001b3

    static func contentSignature(for workout: Workout) -> UInt64 {
        let route = workout.savedRouteName ?? ""
        let basis =
            "\(workout.notes)|\(workout.tss)|\(Int(workout.duration))|\(route)|\(workout.startDate.timeIntervalSince1970)"
        var hash = fnvOffset
        for byte in basis.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* fnvPrime
        }
        return hash
    }

    /// Single-sentence–friendly summary for embedding + coach injection.
    static func chunkText(for workout: Workout) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        var parts: [String] = [
            "Ride on \(df.string(from: workout.startDate)): TSS \(Int(workout.tss)), \(Int(workout.duration / 60)) minutes",
        ]
        if workout.avgPower > 0 {
            parts.append("avg power \(Int(workout.avgPower))W, NP \(Int(workout.normalizedPower))W")
        }
        if workout.avgHR > 0 {
            parts.append("avg HR \(Int(workout.avgHR))")
        }
        if workout.elevationGain > 1 {
            parts.append(String(format: "elevation %.0f m", workout.elevationGain))
        }
        if let r = workout.savedRouteName, !r.isEmpty {
            parts.append("route \(r)")
        }
        if !workout.notes.isEmpty {
            parts.append("notes: \(workout.notes.prefix(280))")
        }
        let line = parts.joined(separator: "; ")
        if line.count > 512 {
            return String(line.prefix(512))
        }
        return line
    }

    static func embeddingLanguage() -> NLLanguage? {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        let primary = NLLanguage(code)
        if NLEmbedding.sentenceEmbedding(for: primary) != nil {
            return primary
        }
        if NLEmbedding.sentenceEmbedding(for: .english) != nil {
            return .english
        }
        logger.debug("No sentence embedding for locale \(code, privacy: .public)")
        return nil
    }
}

// MARK: - Index maintenance

enum WorkoutRAGIndex {
    private static let logger = Logger(subsystem: "com.abchalita.Mangox", category: "WorkoutRAG")

    /// Cap stored chunks to bound SwiftData size and retrieval cost.
    private static let maxStoredChunks = 400
    /// Newest workouts first; only completed valid rides.
    private static let workoutFetchLimit = 450

    private static var lastBackgroundSyncStarted: Date?

    /// Debounced kick from app lifecycle (does not block UI long — processes in batches).
    static func scheduleBackgroundSync(modelContext: ModelContext) {
        let now = Date()
        if let t = lastBackgroundSyncStarted, now.timeIntervalSince(t) < 50 { return }
        lastBackgroundSyncStarted = now

        Task(priority: .utility) { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            do {
                try sync(modelContext: modelContext, maxNewEmbeddings: 80, prune: true)
            } catch {
                logger.error("Workout RAG background sync failed: \(error.localizedDescription)")
            }
        }
    }

    /// Fast path before retrieval: embed a handful of missing recent workouts (MainActor).
    static func ensureRecentIndexed(modelContext: ModelContext, maxNewEmbeddings: Int = 16) {
        do {
            try sync(modelContext: modelContext, maxNewEmbeddings: maxNewEmbeddings, prune: false)
        } catch {
            logger.error("Workout RAG ensureRecentIndexed failed: \(error.localizedDescription)")
        }
    }

    /// Upserts embeddings for workouts that are missing or stale; optionally prunes old chunks.
    static func sync(modelContext: ModelContext, maxNewEmbeddings: Int, prune: Bool) throws {
        guard let lang = WorkoutRAGChunkBuilder.embeddingLanguage(),
            let embedding = NLEmbedding.sentenceEmbedding(for: lang)
        else { return }

        let modelRevision = Int(NLEmbedding.currentSentenceEmbeddingRevision(for: lang))

        let workoutDescriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { $0.statusRaw == "completed" },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        var workouts = (try modelContext.fetch(workoutDescriptor)).filter(\.isValid)
        if workouts.count > workoutFetchLimit {
            workouts = Array(workouts.prefix(workoutFetchLimit))
        }
        let workoutIds = Set(workouts.map(\.id))

        let chunkDescriptor = FetchDescriptor<WorkoutRAGChunk>()
        let existing = try modelContext.fetch(chunkDescriptor)
        var byWorkout: [UUID: WorkoutRAGChunk] = [:]
        for c in existing {
            byWorkout[c.workoutID] = c
        }

        var embedded = 0
        for workout in workouts {
            guard embedded < maxNewEmbeddings else { break }

            let sig = WorkoutRAGChunkBuilder.contentSignature(for: workout)
            if let row = byWorkout[workout.id],
                row.contentSignature == sig,
                row.embeddingModelRevision == modelRevision
            {
                continue
            }

            let text = WorkoutRAGChunkBuilder.chunkText(for: workout)
            guard let vector = embedding.vector(for: text), !vector.isEmpty else { continue }

            if let old = byWorkout[workout.id] {
                modelContext.delete(old)
            }

            let data = WorkoutRAGVectorCodec.encode(vector)
            let chunk = WorkoutRAGChunk(
                workoutID: workout.id,
                startDate: workout.startDate,
                contentSignature: sig,
                embeddingModelRevision: modelRevision,
                chunkText: text,
                embeddingData: data
            )
            modelContext.insert(chunk)
            byWorkout[workout.id] = chunk
            embedded += 1
        }

        var didChange = embedded > 0

        let postUpsert = try modelContext.fetch(chunkDescriptor)
        for c in postUpsert where !workoutIds.contains(c.workoutID) {
            modelContext.delete(c)
            didChange = true
        }

        if prune {
            if try pruneToMax(modelContext: modelContext) {
                didChange = true
            }
        }

        if didChange {
            try modelContext.save()
        }
    }

    /// Returns true if any row was deleted.
    private static func pruneToMax(modelContext: ModelContext) throws -> Bool {
        let descriptor = FetchDescriptor<WorkoutRAGChunk>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        let rows = try modelContext.fetch(descriptor)
        guard rows.count > maxStoredChunks else { return false }
        var removed = false
        for row in rows.dropFirst(maxStoredChunks) {
            modelContext.delete(row)
            removed = true
        }
        return removed
    }
}

// MARK: - Retrieval

enum WorkoutRAGRetriever {
    private static let logger = Logger(subsystem: "com.abchalita.Mangox", category: "WorkoutRAG")

    /// Semantic top-k lines for coach snapshot injection.
    static func appendixIfRelevant(
        userMessage: String,
        modelContext: ModelContext,
        topK: Int = 5,
        minSimilarity: Float = 0.34
    ) -> String? {
        let trimmed = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 6 else { return nil }

        guard let lang = WorkoutRAGChunkBuilder.embeddingLanguage(),
            let embedding = NLEmbedding.sentenceEmbedding(for: lang)
        else { return nil }

        guard let qVec = embedding.vector(for: trimmed), !qVec.isEmpty else { return nil }

        let descriptor = FetchDescriptor<WorkoutRAGChunk>()
        let chunks: [WorkoutRAGChunk]
        do {
            chunks = try modelContext.fetch(descriptor)
        } catch {
            logger.error("Workout RAG fetch failed: \(error.localizedDescription)")
            return nil
        }
        guard !chunks.isEmpty else { return nil }

        var scored: [(Float, String)] = []
        scored.reserveCapacity(chunks.count)

        for chunk in chunks {
            guard let stored = WorkoutRAGVectorCodec.decodeToDouble(chunk.embeddingData),
                let sim = WorkoutRAGVectorCodec.cosineSimilarity(qVec, stored)
            else { continue }
            if sim >= minSimilarity {
                scored.append((sim, chunk.chunkText))
            }
        }

        scored.sort { $0.0 > $1.0 }
        let top = scored.prefix(topK).map(\.1)
        guard !top.isEmpty else { return nil }

        var out = String(
            format: "Semantic ride matches (on-device RAG, cosine ≥ %.2f):\n", minSimilarity)
        out += top.joined(separator: "\n")
        if out.count > 1600 {
            return String(out.prefix(1600)) + "\n…"
        }
        return out
    }
}
