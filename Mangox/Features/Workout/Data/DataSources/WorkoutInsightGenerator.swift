// Features/Workout/Data/DataSources/WorkoutInsightGenerator.swift
// On-device AI generation engine for workout insights and Strava descriptions.
// Domain entity: see Workout/Domain/Entities/WorkoutSummaryInsight.swift
import Foundation
import FoundationModels
import SwiftData

// MARK: - Strava description disk cache

private enum WorkoutStravaDescriptionDiskCache {
    private static let subdir = "WorkoutStravaDescriptions"

    private struct Envelope: Codable {
        var fingerprint: String
        var description: String
    }

    private static var folderURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(subdir, isDirectory: true)
    }

    private static func fileURL(workoutID: UUID) -> URL {
        folderURL.appendingPathComponent("\(workoutID.uuidString).json", isDirectory: false)
    }

    static func load(workoutID: UUID, fingerprint: String) -> String? {
        guard let data = try? Data(contentsOf: fileURL(workoutID: workoutID)),
              let env = try? JSONDecoder().decode(Envelope.self, from: data),
              env.fingerprint == fingerprint
        else { return nil }
        return env.description
    }

    static func save(workoutID: UUID, fingerprint: String, description: String) {
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let env = Envelope(fingerprint: fingerprint, description: description)
        guard let data = try? JSONEncoder().encode(env) else { return }
        try? data.write(to: fileURL(workoutID: workoutID), options: .atomic)
    }

    static func fingerprint(workout: Workout, powerZoneLine: String, ftpWatts: Int) -> String {
        let parts: [String] = [
            String(format: "%.2f", workout.tss),
            String(format: "%.1f", workout.normalizedPower),
            String(format: "%.0f", workout.duration),
            String(format: "%.1f", workout.avgPower),
            powerZoneLine,
            String(ftpWatts),
            workout.savedRouteName ?? "",
        ]
        return "strava_v1:" + parts.joined(separator: "\u{1e}")
    }
}

// MARK: - Insight disk cache (avoid regenerating on every summary open)

private enum WorkoutSummaryInsightDiskCache {
    private static let subdir = "WorkoutSummaryInsights"

    private struct Envelope: Codable {
        var fingerprint: String
        var insight: WorkoutSummaryOnDeviceInsight
    }

    private static var folderURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(subdir, isDirectory: true)
    }

    private static func fileURL(workoutID: UUID) -> URL {
        folderURL.appendingPathComponent("\(workoutID.uuidString).json", isDirectory: false)
    }

    static func load(workoutID: UUID, fingerprint: String) -> WorkoutSummaryOnDeviceInsight? {
        let url = fileURL(workoutID: workoutID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let env = try? JSONDecoder().decode(Envelope.self, from: data), env.fingerprint == fingerprint
        else { return nil }
        return env.insight
    }

    static func save(workoutID: UUID, fingerprint: String, insight: WorkoutSummaryOnDeviceInsight) {
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let env = Envelope(fingerprint: fingerprint, insight: insight)
        guard let data = try? JSONEncoder().encode(env) else { return }
        try? data.write(to: fileURL(workoutID: workoutID), options: .atomic)
    }

    static func fingerprint(
        workout: Workout,
        powerZoneLine: String,
        planLine: String?,
        ftpWatts: Int,
        riderCallName: String?
    ) -> String {
        let notes = String(workout.notes.prefix(200))
        let parts: [String] = [
            "v3",  // bump when adding fields to WorkoutSummaryOnDeviceInsight or changing instructions
            String(format: "%.2f", workout.tss),
            String(format: "%.1f", workout.normalizedPower),
            String(format: "%.0f", workout.duration),
            String(format: "%.1f", workout.avgPower),
            String(workout.maxPower),
            powerZoneLine,
            planLine ?? "",
            String(ftpWatts),
            notes,
            riderCallName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
        ]
        return parts.joined(separator: "\u{1e}")
    }
}

// MARK: - Guided output

@Generable
private struct WorkoutStravaDescriptionGenerated: Equatable {
    @Guide(description: "Internal plan — not shown in UI.")
    var reasoning: String

    @Guide(description: "2-4 sentence natural-language ride story for Strava. Written from the athlete's perspective. First sentence: what the ride was (zone, feel, goal). Remaining sentences: 1-2 highlights from the stats (power, HR, duration, elevation). End with a motivational closer, max 1 sentence. Plain text only — no markdown, no hashtags, max 400 characters total.")
    var body: String
}

@Generable
private struct WorkoutSmartTitleGenerated: Equatable {
    @Guide(description: "Internal plan — not shown in UI.")
    var reasoning: String

    @Guide(
        description:
            "3-6 word ride label for a training app list. Clever or lightly funny is OK if it still matches the real stats (zone, duration, effort). Kind and inclusive — no profanity, slurs, politics, or insults. No quotes. Avoid leading articles (a/the). Reflect dominant zone and duration; skip bland filler like 'workout' or 'session'."
    )
    var title: String
}

@Generable
private struct WorkoutRideInsightGenerated: Equatable {
    var reasoning: String

    @Guide(
        description:
            "One short headline, max 10 words, no quotes. Celebrate the athlete's ride — never imply an app or software did the workout."
    )
    var headline: String

    @Guide(
        description:
            "2-4 factual bullets from the stats only; max 100 chars each. Use you/your or neutral ride wording, not the app as subject.",
        .maximumCount(4)
    )
    var bullets: [String]

    @Guide(description: "Empty string normally; short safety note if needed.")
    var caveat: String

    @Guide(description: "2-3 sentence flowing paragraph coach message. Written to the athlete (second person). Weave together the dominant zone, effort level, and one key takeaway. Encouraging and specific — no generic advice. Max 300 characters.")
    var narrative: String
}

// MARK: - Generation engine (static methods extending the domain entity)

extension WorkoutSummaryOnDeviceInsight {
    /// Locale-aware ride start for the model prompt (avoids ISO timestamps echoed in user-facing copy).
    private static func rideStartDescription(for date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    /// Returns a previously generated insight from disk when inputs still match. Does not call the model.
    @MainActor static func loadCached(
        workout: Workout,
        powerZoneLine: String,
        planLine: String?,
        ftpWatts: Int,
        riderCallName: String? = nil
    ) -> WorkoutSummaryOnDeviceInsight? {
        guard workout.status == .completed, workout.isValid else { return nil }
        let fingerprint = WorkoutSummaryInsightDiskCache.fingerprint(
            workout: workout,
            powerZoneLine: powerZoneLine,
            planLine: planLine,
            ftpWatts: ftpWatts,
            riderCallName: riderCallName
        )
        return WorkoutSummaryInsightDiskCache.load(workoutID: workout.id, fingerprint: fingerprint)
    }

    /// On-device ride takeaway when Apple Intelligence is available; otherwise `nil`.
    /// - Parameter riderCallName: Optional first name (e.g. from Strava) for natural headlines; otherwise copy uses "you/your".
    @MainActor static func generate(
        workout: Workout,
        powerZoneLine: String,
        planLine: String?,
        ftpWatts: Int,
        riderCallName: String? = nil
    ) async -> WorkoutSummaryOnDeviceInsight? {
        guard workout.status == .completed, workout.isValid else { return nil }
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        guard SystemLanguageModel.default.supportsLocale(Locale.current) else { return nil }

        let fingerprint = WorkoutSummaryInsightDiskCache.fingerprint(
            workout: workout,
            powerZoneLine: powerZoneLine,
            planLine: planLine,
            ftpWatts: ftpWatts,
            riderCallName: riderCallName
        )
        if let cached = WorkoutSummaryInsightDiskCache.load(workoutID: workout.id, fingerprint: fingerprint) {
            return cached
        }

        let model = MangoxFoundationModelsSupport.coachSystemLanguageModel()
        let stats = Self.buildStatsPrompt(
            workout: workout,
            powerZoneLine: powerZoneLine,
            planLine: planLine,
            ftpWatts: ftpWatts
        )

        let nameHint: String = {
            let t = riderCallName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if t.isEmpty { return "none (use second person you/your only)" }
            return "optional first name \"\(t)\" — use at most once in the headline if it sounds natural; never in every bullet"
        }()

        let instructions = """
            You summarize one cycling workout for the rider who uses a training app. Version 3.
            Use ONLY the ride statistics block. Do not invent power, TSS, or duration.
            The app did not ride the bike — the human athlete did. Never write that the app name or "Mangox" completed, averaged, held, or rode anything.
            Prefer second person (you/your) or neutral ride-focused sentences ("Solid threshold session", "Strong normalized power").
            If you mention when the ride happened, use natural wording or the same human-readable date style as in the stats — never raw ISO-8601 timestamps in headline or bullets.
            No medical diagnosis; if injury or health appears, set caveat to see a professional.
            Keep tone practical and encouraging. reasoning is internal planning only.
            For narrative: 2-3 sentences, second person, weave dominant zone + effort + one key takeaway. Max 300 characters.
            """

        let session = LanguageModelSession(
            model: model,
            tools: [],
            instructions: Instructions(instructions)
        )

        let prompt = """
            Rider name hint: \(nameHint)

            Ride statistics:
            \(stats)

            Produce headline, bullets, and optional caveat.
            """

        do {
            await MangoxFoundationModelsSupport.logPromptFootprint(
                model: model,
                label: "workout_summary_insight",
                instructions: Instructions(instructions),
                prompt: prompt,
                tools: []
            )
            let response = try await session.respond(
                to: prompt,
                generating: WorkoutRideInsightGenerated.self,
                options: GenerationOptions(sampling: .greedy)
            )
            OnDeviceCoachEngine.logTranscript(session, label: "workout_summary")
            MangoxFoundationModelsSupport.logTranscriptEntries(session, label: "workout_summary")

            let g = response.content
            let caveatTrim = g.caveat.trimmingCharacters(in: .whitespacesAndNewlines)
            let bullets = g.bullets.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter {
                !$0.isEmpty
            }
            let head = g.headline.trimmingCharacters(in: .whitespacesAndNewlines)
            let narrativeTrim = g.narrative.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !head.isEmpty, !bullets.isEmpty else { return nil }
            let built = WorkoutSummaryOnDeviceInsight(
                headline: head,
                bullets: bullets,
                caveat: caveatTrim.isEmpty ? nil : caveatTrim,
                narrative: narrativeTrim.isEmpty ? nil : narrativeTrim
            )
            WorkoutSummaryInsightDiskCache.save(
                workoutID: workout.id,
                fingerprint: fingerprint,
                insight: built
            )
            return built
        } catch {
            MangoxFoundationModelsSupport.logGenerationFailure(error, label: "workout_summary")
            return nil
        }
    }

    // MARK: - Smart title (companion to the insight, stored in Workout.smartTitle)

    /// Generates a 3-6 word descriptive workout label and writes it into `workout.smartTitle`.
    /// Skips generation if `workout.smartTitle` is already set or Apple Intelligence is unavailable.
    @MainActor static func generateSmartTitleIfNeeded(
        workout: Workout,
        powerZoneLine: String,
        ftpWatts: Int
    ) async {
        await generateSmartTitleIfNeeded(
            workout: workout,
            powerZoneLine: powerZoneLine,
            ftpWatts: ftpWatts,
            modelContext: PersistenceContainer.shared.mainContext
        )
    }

    @MainActor static func generateSmartTitleIfNeeded(
        workout: Workout,
        powerZoneLine: String,
        ftpWatts: Int,
        modelContext: ModelContext
    ) async {
        guard workout.status == .completed, workout.isValid else { return }
        guard workout.smartTitle == nil else { return }
        guard OnDeviceCoachEngine.isOnDeviceWritingModelAvailable else {
            workout.smartTitle = OnDeviceModelFallbackCopy.smartWorkoutTitle(
                workout: workout,
                powerZoneLine: powerZoneLine,
                ftpWatts: ftpWatts
            )
            try? modelContext.save()
            return
        }

        let stats = buildStatsPrompt(
            workout: workout, powerZoneLine: powerZoneLine, planLine: nil, ftpWatts: ftpWatts)

        let instructions = """
            Generate a 3-6 word label for a cycling workout based only on the stats.
            You may be witty or playful if it still reflects the real ride — never invent numbers or zones.
            Stay kind and inclusive; no profanity, slurs, politics, or put-downs.
            No quotes, no leading articles (a/the), avoid generic words like "workout" or "session".
            Examples: "Solid Threshold Block", "Legs Called A Meeting", "Easy Endurance Spin", "Tough VO2max Efforts", "Long Sweet Spot", "Recovery Ride".
            reasoning is internal only; title is shown in the UI.
            """
        let model = MangoxFoundationModelsSupport.coachSystemLanguageModel()
        let session = LanguageModelSession(model: model, instructions: Instructions(instructions))

        do {
            let response = try await session.respond(
                to: stats,
                generating: WorkoutSmartTitleGenerated.self,
                options: GenerationOptions(sampling: .greedy)
            )
            let title = response.content.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return }
            workout.smartTitle = title
            try? modelContext.save()
            MangoxFoundationModelsSupport.logTranscriptEntries(session, label: "smart_title")
        } catch {
            MangoxFoundationModelsSupport.logGenerationFailure(error, label: "workout_smart_title")
            if workout.smartTitle == nil {
                workout.smartTitle = OnDeviceModelFallbackCopy.smartWorkoutTitle(
                    workout: workout,
                    powerZoneLine: powerZoneLine,
                    ftpWatts: ftpWatts
                )
                try? modelContext.save()
            }
        }
    }

    // MARK: - AI Strava description

    /// Generates a natural-language Strava description and caches it to disk by workout fingerprint.
    /// Returns the cached description instantly on subsequent calls. Returns `nil` when Apple
    /// Intelligence is unavailable or the workout is incomplete.
    @MainActor static func generateStravaDescription(
        workout: Workout,
        powerZoneLine: String,
        ftpWatts: Int
    ) async -> String? {
        guard workout.status == .completed, workout.isValid else { return nil }
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        guard SystemLanguageModel.default.supportsLocale(Locale.current) else { return nil }

        let fingerprint = WorkoutStravaDescriptionDiskCache.fingerprint(
            workout: workout, powerZoneLine: powerZoneLine, ftpWatts: ftpWatts)
        if let cached = WorkoutStravaDescriptionDiskCache.load(workoutID: workout.id, fingerprint: fingerprint) {
            return cached
        }

        let stats = buildStatsPrompt(
            workout: workout, powerZoneLine: powerZoneLine, planLine: nil, ftpWatts: ftpWatts)

        let instructions = """
            Write a short Strava activity description for an indoor cycling workout.
            Use the statistics block only — never invent numbers.
            Write in first person past tense (I, my). Keep it conversational and specific to the stats.
            No markdown, no hashtags, no app names. Max 400 characters for `body`.
            reasoning is internal only.
            """
        let model = MangoxFoundationModelsSupport.coachSystemLanguageModel()
        let session = LanguageModelSession(model: model, instructions: Instructions(instructions))

        do {
            await MangoxFoundationModelsSupport.logPromptFootprint(
                model: model, label: "strava_description", instructions: Instructions(instructions),
                prompt: stats, tools: [])
            let response = try await session.respond(
                to: stats,
                generating: WorkoutStravaDescriptionGenerated.self,
                options: GenerationOptions(sampling: .greedy)
            )
            MangoxFoundationModelsSupport.logTranscriptEntries(session, label: "strava_description")
            let body = response.content.body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { return nil }
            WorkoutStravaDescriptionDiskCache.save(
                workoutID: workout.id, fingerprint: fingerprint, description: body)
            return body
        } catch {
            MangoxFoundationModelsSupport.logGenerationFailure(error, label: "strava_description")
            return nil
        }
    }

    private static func buildStatsPrompt(
        workout: Workout,
        powerZoneLine: String,
        planLine: String?,
        ftpWatts: Int
    ) -> String {
        let durMin = max(1, Int(workout.duration / 60))
        let dateStr = Self.rideStartDescription(for: workout.startDate)
        var lines: [String] = []
        lines.append("Date: \(dateStr)")
        lines.append("Duration active: \(durMin) min")
        lines.append("TSS: \(Int(workout.tss.rounded()))")
        lines.append("IF: \(String(format: "%.2f", workout.intensityFactor))")
        lines.append("Avg power: \(Int(workout.avgPower.rounded())) W, NP: \(Int(workout.normalizedPower.rounded())) W")
        lines.append("Max power: \(workout.maxPower) W")
        if workout.avgHR > 0 {
            lines.append("Avg HR: \(Int(workout.avgHR.rounded())), max HR: \(workout.maxHR)")
        }
        if workout.distance > 0 {
            lines.append(
                String(
                    format: "Distance: %.2f km, avg speed: %.1f km/h",
                    workout.distance / 1000,
                    workout.displayAverageSpeedKmh
                ))
        }
        if workout.elevationGain > 0 {
            lines.append(String(format: "Elevation gain: %.0f m", workout.elevationGain))
        }
        if let name = workout.savedRouteName, !name.isEmpty {
            lines.append("Route: \(name)")
        }
        lines.append("Rider FTP setting (reference, not a person): \(ftpWatts) W")
        lines.append("Time in power zones (percent of ride): \(powerZoneLine)")
        if let planLine, !planLine.isEmpty {
            lines.append("Plan context: \(planLine)")
        }
        if !workout.notes.isEmpty {
            lines.append("Rider notes: \(workout.notes.prefix(400))")
        }
        return lines.joined(separator: "\n")
    }
}
