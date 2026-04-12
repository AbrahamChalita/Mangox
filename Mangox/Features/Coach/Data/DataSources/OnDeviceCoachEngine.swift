import Foundation
import FoundationModels
import SwiftData
import os
import os.log

// MARK: - Prompt versioning (bump when instructions change materially)

enum CoachOnDevicePromptVersion {
    static let routing = 1
    static let narrow = 6
    static let quickPrompts = 3
}

/// - `MangoxCoachFMVerboseLog`: full `LanguageModelSession.transcript` string after calls.
/// - `MangoxCoachFMTranscriptDebug`: log each `Transcript.Entry` (see `MangoxFoundationModelsSupport`).
/// - `MangoxCoachFMTokenLog`: instruction/prompt/tool token estimates (DEBUG on by default).
enum CoachFoundationModelsLogging {
    static let verboseTranscriptDefaultsKey = "MangoxCoachFMVerboseLog"

    static var verboseTranscriptEnabled: Bool {
        UserDefaults.standard.bool(forKey: verboseTranscriptDefaultsKey)
    }
}

private let foundationModelsSignpostLog = OSLog(
    subsystem: "com.abchalita.Mangox", category: "FoundationModels")

// MARK: - Guided generation: routing

@Generable
enum CoachRouteKind: String, Equatable {
    case cloudCoach
    case localNarrowReply
}

@Generable
struct CoachRouteDecision: Equatable {
    @Guide(description: "One short internal sentence; not shown in the UI.")
    var reasoning: String

    @Guide(
        description:
            "cloudCoach for plans, web, deep coaching, or uncertainty. localNarrowReply only for simple questions answerable from app stats."
    )
    var route: CoachRouteKind
}

// MARK: - Guided generation: narrow reply

@Generable
struct NarrowSuggestedAction: Equatable {
    @Guide(
        description:
            "Short follow-up question or action the user might want to ask next, max 6 words. First person or imperative (e.g. 'Show my TSS trend', 'What is my FTP?'). No punctuation except question marks."
    )
    var label: String
}

@Generable
struct NarrowCoachReply: Equatable {
    @Guide(description: "Brief internal plan, not shown in the UI.")
    var reasoning: String

    @Guide(
        description:
            "Coach reply in plain language, max about 1200 characters. Use ONLY power/TSS/HR/plan facts from the verified training snapshot. Must be a single paragraph."
    )
    var body: String

    @Guide(description: "Optional one short follow-up question; empty string if none.")
    var followUp: String

    @Guide(
        description:
            "1-3 short tappable follow-up chips the user might want next. Empty array if no obvious next step.",
        .maximumCount(3))
    var suggestedActions: [NarrowSuggestedAction]
}

// MARK: - Guided generation: single workout

@Generable
struct OnDeviceWorkoutInterval: Equatable {
    var name: String
    var durationSeconds: Int
    var zone: String
    var repeats: Int
    var cadenceLow: Int?
    var cadenceHigh: Int?
    var recoverySeconds: Int
    var recoveryZone: String
    var notes: String
    var suggestedTrainerMode: String
    var simulationGrade: Double?
}

@Generable
struct OnDeviceGeneratedWorkout: Equatable {
    var reasoning: String
    var title: String
    var purpose: String
    var rationale: String
    var goal: String
    var durationMinutes: Int
    var zone: String
    var notes: String
    var intervals: [OnDeviceWorkoutInterval]
}

// MARK: - Guided generation: quick prompts

@Generable
struct QuickPromptPack: Equatable {
    @Guide(description: "Exactly four starter prompts for a cycling coach chat.")
    @Guide(.count(4))
    var items: [QuickPromptItem]
}

@Generable
struct QuickPromptItem: Equatable {
    @Guide(
        description:
            "Short phrase the USER would send to the coach (first person / my / how do I), max 8 words. Not a question from the coach to the user."
    )
    var text: String

    @Guide(description: "SF Symbol name such as chart.bar.fill or bolt.fill")
    var icon: String
}

// MARK: - Content tagging (SystemLanguageModel.useCase.contentTagging)

@Generable
struct CoachStarterContentTags: Equatable {
    @Guide(
        description: "Most relevant indoor cycling / training topic tags, lowercase.",
        .maximumCount(5))
    var topics: [String]
}

// MARK: - Home training insight (guided generation)

@Generable
private struct HomeTrainingInsightGenerated: Equatable {
    @Guide(description: "Internal plan — not shown in UI.")
    var reasoning: String

    @Guide(
        description:
            "Exactly one or two words for a UI badge (Title Case). Summarize training readiness from the data only — no punctuation, no quotes. Examples: Optimal, Recovery day, Build week, Easy spin, High load."
    )
    var statusLabel: String
}

// MARK: - Home insight cache (UserDefaults, 8-hour TTL)

private enum HomeInsightCache {
    private static let key = "mangox_home_insight_v3"
    private static let ttl: TimeInterval = 3600 * 8

    private struct Stored: Codable {
        var fingerprint: String
        var insight: String
        var generatedAt: Date
    }

    static func load(fingerprint: String) -> String? {
        guard let data = UserDefaults.standard.data(forKey: key),
            let stored = try? JSONDecoder().decode(Stored.self, from: data),
            stored.fingerprint == fingerprint,
            Date().timeIntervalSince(stored.generatedAt) < ttl
        else { return nil }
        return stored.insight
    }

    static func save(fingerprint: String, insight: String) {
        guard
            let data = try? JSONEncoder().encode(
                Stored(fingerprint: fingerprint, insight: insight, generatedAt: .now))
        else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

// MARK: - Guided generation: pre-ride briefing

@Generable
private struct RideBriefingGenerated: Equatable {
    @Guide(description: "Internal plan — not shown in UI.")
    var reasoning: String

    @Guide(
        description:
            "2-3 sentence pre-ride briefing for the athlete. Cover: (1) what the workout is (zones + total duration), (2) one key execution tip (e.g. 'Stay seated in the first interval', 'Aim for 90 rpm in Z4'), (3) a short motivating closer. Second person, present tense. Max 240 characters."
    )
    var briefing: String
}

// MARK: - Guided generation: Instagram caption

@Generable
private struct InstagramCaptionGenerated: Equatable {
    @Guide(description: "Internal plan — not shown in UI.")
    var reasoning: String

    @Guide(
        description:
            "2-3 sentence Instagram caption for a cycling workout. First person, past tense. Specific to the stats — mention the dominant zone, NP/power, or duration if notable. Energetic but not over-the-top. End with 1-2 relevant hashtags (e.g. #cycling #indoorcycling #zwift). Max 280 characters total."
    )
    var caption: String
}

// MARK: - Guided generation: story card title

@Generable
private struct StoryCardTitleGenerated: Equatable {
    @Guide(description: "Internal plan — not shown in UI.")
    var reasoning: String

    @Guide(
        description:
            "2-4 word punchy, poster-style headline for a cycling ride summary card. Title-case. No punctuation, no hashtags, no numbers. Reflect the ride's essence through zone, effort, or terrain. Examples: 'Threshold Destroyer', 'Alpine Grind', 'Zone Five Ignition', 'Endurance Foundation'. Max 28 characters."
    )
    var title: String
}

// MARK: - Guided generation: coach session title

@Generable
private struct ChatSessionTitleGenerated: Equatable {
    @Guide(description: "Internal plan — not shown in UI.")
    var reasoning: String

    @Guide(
        description:
            "3-5 word session title, title-case, no punctuation. Reflect the topic of the conversation (e.g. 'Zone 2 Recovery Plan', 'FTP Week Check-In', 'Race Prep Advice'). Never use generic titles like 'New Conversation' or 'Cycling Chat'."
    )
    var title: String
}

// MARK: - Engine

enum OnDeviceCoachEngine {
    private static let logger = Logger(subsystem: "com.abchalita.Mangox", category: "OnDeviceCoach")

    static var isSystemModelAvailable: Bool {
        switch SystemLanguageModel.default.availability {
        case .available: return true
        default: return false
        }
    }

    /// For debugging (Console): why `SystemLanguageModel.default` is not `.available` (device, OS, region, Apple Intelligence off, etc.).
    static var systemModelAvailabilityLogDescription: String {
        String(describing: SystemLanguageModel.default.availability)
    }

    static var isContentTaggingModelAvailable: Bool {
        let m = SystemLanguageModel(useCase: .contentTagging)
        switch m.availability {
        case .available: return true
        default: return false
        }
    }

    /// Logs `LanguageModelSession.transcript` when verbose logging is enabled (Instruments + Console).
    static func logTranscript(_ session: LanguageModelSession, label: String) {
        guard CoachFoundationModelsLogging.verboseTranscriptEnabled else { return }
        logger.info(
            "FM transcript [\(label)]: \(String(describing: session.transcript), privacy: .public)")
    }

    /// Point Instruments **os_signpost** at subsystem `com.abchalita.Mangox`, category **FoundationModels**, name **FMOnDeviceNarrow**.
    static func signpostOnDeviceNarrow<T>(_ work: () async throws -> T) async rethrows -> T {
        let sid = OSSignpostID(log: foundationModelsSignpostLog)
        os_signpost(
            .begin, log: foundationModelsSignpostLog, name: "FMOnDeviceNarrow", signpostID: sid)
        defer {
            os_signpost(
                .end, log: foundationModelsSignpostLog, name: "FMOnDeviceNarrow", signpostID: sid)
        }
        return try await work()
    }

    /// Keyword guardrails: never route “heavy” intents to the narrow on-device path.
    static func heuristicCloudRoute(for message: String) -> Bool {
        let lower = message.lowercased()
        let cloudKeywords = [
            "plan for", "training plan", "generate a plan", "build me a plan", "build a plan",
            "periodization", "macrocycle", "mesocycle", "race plan", "event plan",
            "web search", "search the", "look up online", "article", "study",
            "compare ", "vs ", "versus",
            "write code", "swift code", "python",
        ]
        if cloudKeywords.contains(where: { lower.contains($0) }) { return true }
        if lower.count > 800 { return true }
        return false
    }

    static func heuristicLocalPreferred(for message: String) -> Bool {
        let lower = message.lowercased()
        let localHints = [
            "ftp", "tss", "recovery", "today", "this week", "week load",
            "how tired", "yesterday", "normalized", "np ", "heart rate", "max hr",
        ]
        return localHints.contains(where: { lower.contains($0) })
    }

    static func classifyRoute(
        userMessage: String,
        factSheet: String
    ) async throws -> CoachRouteKind {
        try MangoxFoundationModelsSupport.throwIfLocaleUnsupported()

        let instructions = """
            You route Mangox cycling coach messages. Mangox is an indoor/training app with FTP, TSS, and plans stored on-device.
            Version \(CoachOnDevicePromptVersion.routing).
            Rules:
            - Choose cloudCoach for: multi-week plans, race prep design, medical advice, anything needing web, long essays, or if unsure.
            - Choose localNarrowReply only for short factual questions that can be answered from FTP/TSS/last ride/active plan summaries (the fact sheet).
            - When in doubt, choose cloudCoach.
            """

        let model = MangoxFoundationModelsSupport.coachSystemLanguageModel()
        let session = LanguageModelSession(
            model: model,
            tools: [],
            instructions: Instructions(instructions)
        )
        let prompt = """
            User message:
            \(userMessage)

            Fact sheet (may be partial):
            \(factSheet)
            """
        await MangoxFoundationModelsSupport.logPromptFootprint(
            model: model,
            label: "coach_route",
            instructions: Instructions(instructions),
            prompt: prompt,
            tools: []
        )
        do {
            let decision = try await session.respond(
                to: prompt,
                generating: CoachRouteDecision.self,
                options: GenerationOptions(sampling: .greedy)
            )
            logTranscript(session, label: "route")
            MangoxFoundationModelsSupport.logTranscriptEntries(session, label: "route")
            return decision.content.route
        } catch {
            MangoxFoundationModelsSupport.logGenerationFailure(error, label: "coach_route")
            throw error
        }
    }

    // MARK: - Narrow session factory

    /// Shared instructions — used at session creation and for token-budget logging.
    private static var narrowInstructionsText: String {
        """
        You are Mangox's on-device cycling assistant. Be concise and practical.
        Version \(CoachOnDevicePromptVersion.narrow).
        The Training snapshot block is verified Mangox data. You also have tools for deeper on-device facts (recent rides, extended rider fields, FTP test history).
        Call tools when needed; you may issue parallel tool calls. Never invent FTP, watts, TSS, distances, or dates not present in the snapshot or tool outputs.
        If data is missing, say what is missing and suggest Settings or syncing rides.
        No markdown headings. Write as a single continuous paragraph without any newlines or bullets. Answer directly using only the provided facts.
        Fill `reasoning` first with a short internal plan, then `body`, then optional `followUp`.
        """
    }

    /// Creates a reusable multi-turn session for the narrow on-device coach path.
    /// Caller should store this in AIService and reuse across turns; reset on createNewSession/switchToSession.
    /// Tools are bound at session creation — data is snapshotted at that moment.
    static func makeNarrowSession(tools: [any Tool]) -> LanguageModelSession {
        let model = MangoxFoundationModelsSupport.coachSystemLanguageModel()
        return LanguageModelSession(
            model: model,
            tools: tools,
            instructions: Instructions(narrowInstructionsText)
        )
    }

    /// Streams partial `NarrowCoachReply` for UI. Baseline snapshot is inlined per-turn; tools were
    /// bound at session creation via `makeNarrowSession`. Reuse the same session across turns so the
    /// model retains prior exchange context (multi-turn memory).
    static func streamNarrowReply(
        userMessage: String,
        trainingSnapshot: String,
        session: LanguageModelSession,
        onPartial: (NarrowCoachReply.PartiallyGenerated) async -> Void
    ) async throws -> NarrowCoachReply? {
        try MangoxFoundationModelsSupport.throwIfLocaleUnsupported()

        let composedPrompt = """
            Training snapshot (verified Mangox baseline):
            \(trainingSnapshot)

            User question:
            \(userMessage)
            """

        let model = MangoxFoundationModelsSupport.coachSystemLanguageModel()
        await MangoxFoundationModelsSupport.logPromptFootprint(
            model: model,
            label: "coach_narrow",
            instructions: Instructions(narrowInstructionsText),
            prompt: composedPrompt,
            tools: []  // tools are session-level; logged once at makeNarrowSession creation
        )

        let stream = session.streamResponse(
            generating: NarrowCoachReply.self,
            includeSchemaInPrompt: false,
            options: GenerationOptions(sampling: .greedy)
        ) {
            composedPrompt
        }

        var lastPartial: NarrowCoachReply.PartiallyGenerated?
        do {
            for try await snapshot in stream {
                lastPartial = snapshot.content
                if let lastPartial {
                    await onPartial(lastPartial)
                }
            }
        } catch {
            MangoxFoundationModelsSupport.logGenerationFailure(error, label: "coach_narrow_stream")
            throw error
        }

        logTranscript(session, label: "narrow_stream")
        MangoxFoundationModelsSupport.logTranscriptEntries(session, label: "narrow_stream")
        MangoxFoundationModelsSupport.logFeedbackAttachmentIfEnabled(
            session: session, sentiment: nil, issues: [])
        guard let last = lastPartial else { return nil }
        return finalizedNarrowReply(from: last)
    }

    static func finalizedNarrowReply(from partial: NarrowCoachReply.PartiallyGenerated)
        -> NarrowCoachReply?
    {
        let body = partial.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !body.isEmpty else { return nil }
        let actions = (partial.suggestedActions ?? []).compactMap { p -> NarrowSuggestedAction? in
            guard let label = p.label?.trimmingCharacters(in: .whitespacesAndNewlines),
                !label.isEmpty
            else { return nil }
            return NarrowSuggestedAction(label: label)
        }
        return NarrowCoachReply(
            reasoning: partial.reasoning?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            body: body,
            followUp: partial.followUp?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            suggestedActions: Array(actions.prefix(3))
        )
    }

    static func generateQuickPrompts(factSheet: String) async throws -> QuickPromptPack {
        try MangoxFoundationModelsSupport.throwIfLocaleUnsupported()

        let instructions = """
            Propose four short starter prompts shown as tappable chips in a cycling coach chat (FTP, training plans, indoor rides).
            Version \(CoachOnDevicePromptVersion.quickPrompts).
            Each item.text is exactly what the USER would type or tap to ask the coach — first person or "my …", e.g. "How hard was my last ride?", "What should I do for recovery today?", "Explain my power zones".
            Wrong style (do not output): coach-to-user questions like "How did you feel?", "Want to review your week?", "Should we check your FTP?".
            Only suggest prompts that are supported by the rider context provided below.
            Do not mention a last ride if there is no ride history.
            Do not mention FTP history or "last FTP" if no FTP history is provided.
            Do not mention an active plan or today's planned workout if no plan exists.
            Do not mention WHOOP or recovery metrics unless WHOOP recovery data is present.
            Be specific to the rider context when possible; otherwise sensible defaults grounded in the available data.
            No quotation marks in text. Keep under 8 words per item.
            Icons must be valid SF Symbol names (snake case with dots), e.g. chart.bar.fill, bolt.fill, calendar.badge.clock.
            """

        let model = MangoxFoundationModelsSupport.coachSystemLanguageModel()
        let session = LanguageModelSession(
            model: model,
            tools: [],
            instructions: Instructions(instructions)
        )
        let prompt = """
            Rider context:
            \(factSheet)
            """
        await MangoxFoundationModelsSupport.logPromptFootprint(
            model: model,
            label: "coach_quick_prompts",
            instructions: Instructions(instructions),
            prompt: prompt,
            tools: []
        )
        do {
            let pack = try await session.respond(
                to: prompt,
                generating: QuickPromptPack.self,
                options: GenerationOptions(sampling: .greedy)
            )
            logTranscript(session, label: "quick_prompts")
            MangoxFoundationModelsSupport.logTranscriptEntries(session, label: "quick_prompts")
            return pack.content
        } catch {
            MangoxFoundationModelsSupport.logGenerationFailure(error, label: "coach_quick_prompts")
            throw error
        }
    }

    /// Topic-style tags for empty-state chips (Apple’s content tagging use case).
    static func generateStarterTopicTags(factSheet: String) async throws -> [String] {
        guard isContentTaggingModelAvailable else { return [] }

        let model = SystemLanguageModel(useCase: .contentTagging)
        guard model.supportsLocale(Locale.current) else { return [] }

        let instructions = """
            Summarize this cyclist app context into short topic tags (training load, ftp, recovery, plans, etc.).
            Up to five tags; lowercase; one to three words each; no punctuation except hyphen.
            """
        let session = LanguageModelSession(model: model, instructions: Instructions(instructions))
        await MangoxFoundationModelsSupport.logPromptFootprint(
            model: model,
            label: "coach_content_tags",
            instructions: Instructions(instructions),
            prompt: factSheet,
            tools: []
        )
        do {
            let response = try await session.respond(
                to: factSheet,
                generating: CoachStarterContentTags.self,
                options: GenerationOptions(sampling: .greedy)
            )
            logTranscript(session, label: "content_tagging")
            MangoxFoundationModelsSupport.logTranscriptEntries(session, label: "content_tagging")
            var seen = Set<String>()
            var out: [String] = []
            for raw in response.content.topics {
                let t = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard t.count >= 2, t.count <= 32 else { continue }
                if seen.insert(t).inserted {
                    out.append(t)
                }
                if out.count >= 5 { break }
            }
            return out
        } catch {
            MangoxFoundationModelsSupport.logGenerationFailure(error, label: "coach_content_tags")
            throw error
        }
    }

    // MARK: - Allowed SF Symbols for generated quick prompts

    private static let allowedQuickPromptIcons: Set<String> = [
        "chart.bar.fill", "bolt.fill", "heart.fill", "calendar.badge.clock",
        "figure.outdoor.cycle", "figure.run", "speedometer", "flame.fill",
        "moon.zzz.fill", "sun.max.fill", "arrow.triangle.2.circlepath",
        "timer", "metronome", "waveform.path.ecg", "bed.double.fill",
    ]

    static func sanitizeQuickPromptItems(_ items: [QuickPromptItem]) -> [(
        text: String, icon: String
    )] {
        items.prefix(4).map { item in
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let iconRaw = item.icon.trimmingCharacters(in: .whitespacesAndNewlines)
            let icon =
                allowedQuickPromptIcons.contains(iconRaw)
                ? iconRaw
                : "bubble.left.fill"
            return (text, icon)
        }
        .filter { !$0.text.isEmpty }
    }

    // MARK: - Pre-ride workout briefing

    /// Generates a 2-3 sentence pre-ride briefing for a guided workout session.
    /// Returns nil when Apple Intelligence is unavailable or no structured intervals exist.
    static func generateRideBriefing(
        dayTitle: String,
        dayNotes: String,
        timeline: [TimelineStep],
        ftpWatts: Int
    ) async -> String? {
        guard !timeline.isEmpty else { return nil }
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        guard SystemLanguageModel.default.supportsLocale(Locale.current) else { return nil }

        // Build a compact structured interval summary for the prompt
        let totalMin = max(1, (timeline.last?.endOffset ?? 0) / 60)
        let zoneCounts: [String: Int] = timeline.reduce(into: [:]) { acc, step in
            let label = step.zone.rawValue
            acc[label, default: 0] += 1
        }
        let zonesSummary = zoneCounts.sorted { $0.value > $1.value }
            .prefix(3)
            .map { "\($0.key)×\($0.value)" }
            .joined(separator: ", ")
        let stepSummary = timeline.prefix(6).map { step in
            let min = max(1, step.durationSeconds / 60)
            return "\(step.zone.rawValue) \(min)min"
        }.joined(separator: " → ")

        var facts: [String] = [
            "Workout: \(dayTitle)",
            "Total duration: \(totalMin) min",
            "Zones (most frequent): \(zonesSummary)",
            "Step sequence (first 6): \(stepSummary)",
            "FTP: \(ftpWatts) W",
        ]
        if !dayNotes.isEmpty { facts.append("Notes: \(dayNotes.prefix(200))") }

        let instructions = """
            Write a short pre-ride briefing for an indoor cycling workout. Max 240 characters.
            Mention what type of workout it is, give one specific execution tip, and close with a short encouragement.
            Plain text, second person (you / your). reasoning is internal only.
            """
        let model = MangoxFoundationModelsSupport.coachSystemLanguageModel()
        let session = LanguageModelSession(model: model, instructions: Instructions(instructions))
        do {
            let response = try await session.respond(
                to: facts.joined(separator: "\n"),
                generating: RideBriefingGenerated.self,
                options: GenerationOptions(sampling: .greedy)
            )
            MangoxFoundationModelsSupport.logTranscriptEntries(session, label: "ride_briefing")
            let text = response.content.briefing.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch {
            MangoxFoundationModelsSupport.logGenerationFailure(error, label: "ride_briefing")
            return nil
        }
    }

    // MARK: - Instagram story caption

    /// Generates a short Instagram story caption for a completed ride.
    static func generateInstagramCaption(
        workout: Workout,
        dominantZoneName: String,
        routeName: String?,
        ftpWatts: Int,
        powerZoneLine: String
    ) async -> String? {
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        guard SystemLanguageModel.default.supportsLocale(Locale.current) else { return nil }

        let durMin = max(1, Int(workout.duration / 60))
        var facts: [String] = [
            "Duration: \(durMin) min",
            "Dominant zone: \(dominantZoneName)",
            "Avg power: \(Int(workout.avgPower.rounded())) W, NP: \(Int(workout.normalizedPower.rounded())) W",
            "TSS: \(Int(workout.tss.rounded()))",
            "IF: \(String(format: "%.2f", workout.intensityFactor))",
        ]
        if let route = routeName, !route.isEmpty { facts.append("Route: \(route)") }
        if workout.elevationGain > 0 {
            facts.append(String(format: "Elevation: %.0f m", workout.elevationGain))
        }
        facts.append("FTP: \(ftpWatts) W")
        facts.append("Power zones: \(powerZoneLine)")

        let instructions = """
            Write a short Instagram caption for an indoor cycling ride.
            Use the stats block only — never invent numbers.
            Be specific, energetic, and personal. Plain text plus 1-2 relevant hashtags.
            Max 280 characters. reasoning is internal only.
            """
        let model = MangoxFoundationModelsSupport.coachSystemLanguageModel()
        let session = LanguageModelSession(model: model, instructions: Instructions(instructions))
        do {
            let response = try await session.respond(
                to: facts.joined(separator: "\n"),
                generating: InstagramCaptionGenerated.self,
                options: GenerationOptions(sampling: .greedy)
            )
            MangoxFoundationModelsSupport.logTranscriptEntries(session, label: "ig_caption")
            let caption = response.content.caption.trimmingCharacters(in: .whitespacesAndNewlines)
            return caption.isEmpty ? nil : caption
        } catch {
            MangoxFoundationModelsSupport.logGenerationFailure(error, label: "ig_caption")
            return nil
        }
    }

    // MARK: - Story card headline

    /// Generates a 2-4 word punchy poster headline for the Instagram story card bitmap.
    /// Returns nil when Apple Intelligence is unavailable or the result is empty.
    static func generateStoryCardTitle(
        workout: Workout,
        dominantZoneName: String,
        routeName: String?,
        totalElevationGain: Double
    ) async -> String? {
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        guard SystemLanguageModel.default.supportsLocale(Locale.current) else { return nil }

        let durMin = max(1, Int(workout.duration / 60))
        var facts: [String] = [
            "Duration: \(durMin) min",
            "Dominant zone: \(dominantZoneName)",
            "Avg power: \(Int(workout.avgPower.rounded())) W",
            "TSS: \(Int(workout.tss.rounded()))",
            "IF: \(String(format: "%.2f", workout.intensityFactor))",
        ]
        if let route = routeName, !route.isEmpty { facts.append("Route: \(route)") }
        if totalElevationGain > 50 {
            facts.append(String(format: "Elevation: %.0f m", totalElevationGain))
        }
        if workout.distance > 0 {
            facts.append(String(format: "Distance: %.1f km", workout.distance / 1000))
        }

        let instructions = """
            Write a 2-4 word punchy, poster-style headline for a cycling ride summary card.
            Title-case. No punctuation, no hashtags, no numbers.
            Reflect the ride's essence through zone, effort level, or terrain.
            Examples: 'Threshold Destroyer', 'Alpine Grind', 'Zone Five Ignition', 'Endurance Foundation'.
            Max 28 characters. reasoning is internal only.
            """
        let model = MangoxFoundationModelsSupport.coachSystemLanguageModel()
        let session = LanguageModelSession(model: model, instructions: Instructions(instructions))
        do {
            let response = try await session.respond(
                to: facts.joined(separator: "\n"),
                generating: StoryCardTitleGenerated.self,
                options: GenerationOptions(sampling: .greedy)
            )
            MangoxFoundationModelsSupport.logTranscriptEntries(session, label: "ig_card_title")
            let title = response.content.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? nil : title
        } catch {
            MangoxFoundationModelsSupport.logGenerationFailure(error, label: "ig_card_title")
            return nil
        }
    }

    // MARK: - Coach session title

    /// Generates a descriptive 3-5 word title for a coach chat session from the first user+assistant exchange.
    /// Returns nil when Apple Intelligence is unavailable or the result is empty.
    static func generateSessionTitle(
        firstUserMessage: String,
        firstAssistantReply: String
    ) async -> String? {
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        guard SystemLanguageModel.default.supportsLocale(Locale.current) else { return nil }

        let instructions = """
            Generate a short 3-5 word title for a cycling coach chat session.
            The title should reflect the specific topic, not be generic.
            reasoning is internal only; title appears in the app sidebar.
            """
        let model = MangoxFoundationModelsSupport.coachSystemLanguageModel()
        let session = LanguageModelSession(model: model, instructions: Instructions(instructions))
        let prompt = """
            User: \(firstUserMessage.prefix(400))
            Coach: \(firstAssistantReply.prefix(600))
            """
        do {
            let response = try await session.respond(
                to: prompt,
                generating: ChatSessionTitleGenerated.self,
                options: GenerationOptions(sampling: .greedy)
            )
            let title = response.content.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? nil : title
        } catch {
            MangoxFoundationModelsSupport.logGenerationFailure(error, label: "session_title")
            return nil
        }
    }

    // MARK: - Home training insight

    /// Short readiness label (one or two words) for the home training status badge. Empty if generation fails.
    static func generateHomeTrainingInsight(factSheet: String) async throws -> String {
        try MangoxFoundationModelsSupport.throwIfLocaleUnsupported()

        let fingerprint = String(factSheet.prefix(480))
        if let cached = HomeInsightCache.load(fingerprint: fingerprint) {
            return sanitizeHomeStatusLabel(cached)
        }

        let instructions = """
            You are a concise cycling coach assistant. Output a statusLabel of exactly ONE or TWO words (Title Case) capturing training readiness for today.
            Base it ONLY on the metrics provided. No sentences, no punctuation, no medical claims, no generic cheerleading.
            """
        let model = MangoxFoundationModelsSupport.coachSystemLanguageModel()
        let session = LanguageModelSession(model: model, instructions: Instructions(instructions))

        let response = try await session.respond(
            to: "Rider metrics:\n\(factSheet)",
            generating: HomeTrainingInsightGenerated.self,
            options: GenerationOptions(sampling: .greedy)
        )
        let raw = response.content.statusLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = sanitizeHomeStatusLabel(raw)
        guard !label.isEmpty else { return "" }
        HomeInsightCache.save(fingerprint: fingerprint, insight: label)
        logTranscript(session, label: "home_insight")
        MangoxFoundationModelsSupport.logTranscriptEntries(session, label: "home_insight")
        return label
    }

    /// Keeps at most two words for the badge; strips stray punctuation.
    private static func sanitizeHomeStatusLabel(_ raw: String) -> String {
        let trimmed =
            raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?\"'"))
        let parts = trimmed.split { $0.isWhitespace || $0.isNewline }.map(String.init).filter {
            !$0.isEmpty
        }
        guard !parts.isEmpty else { return "" }
        let joined = parts.prefix(2).joined(separator: " ")
        return joined.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - AIService: fact sheet + tool factory

extension AIService {
    struct CoachStarterPromptAvailability {
        let hasRecentRide: Bool
        let hasAnyRideData: Bool
        let hasFTPHistory: Bool
        let hasActivePlan: Bool
        let hasWhoopRecovery: Bool
    }

    func coachFactSheetText() -> String {
        coachFactSheetText(modelContext: persistenceContext)
    }

    func loadCoachEmptyStartersContent() async -> CoachEmptyStartersContent {
        await loadCoachEmptyStartersContent(modelContext: persistenceContext)
    }

    func contextualQuickPrompts() -> [QuickPrompt] {
        contextualQuickPrompts(modelContext: persistenceContext)
    }

    /// Compact context for on-device prompts (token-aware; keep under ~1.5k chars).
    func coachFactSheetText(modelContext: ModelContext) -> String {
        let ctx = buildUserContext(modelContext: modelContext)
        let recovery = recoveryStatus(modelContext: modelContext)
        var lines: [String] = []
        lines.append(
            "Rider: FTP \(ctx.ftp)W, max HR \(ctx.maxHR), resting HR \(ctx.restingHR).")
        if let w = ctx.riderWeightKg, w > 0 {
            lines.append(String(format: "Weight: %.1f kg.", w))
        }
        if let age = ctx.riderAge, age > 0 {
            lines.append("Age: \(age) years.")
        }
        lines.append("Completed workouts (last 30d): \(ctx.recentWorkoutsCount).")
        lines.append("This calendar week TSS (completed valid rides): \(ctx.weekActualTss).")
        if ctx.whoopLinked, let pct = ctx.whoopRecoveryPercent {
            let rhr = ctx.whoopRestingHR.map { "\($0) bpm" } ?? "n/a"
            let hrv = ctx.whoopHrvMs.map { "\($0) ms" } ?? "n/a"
            let mhr = ctx.whoopMaxHeartRate.map { "\($0) bpm" } ?? "n/a"
            lines.append(
                "WHOOP recovery \(Int(pct))% (RHR \(rhr), HRV \(hrv), profile max HR \(mhr)). Readiness label: \(recovery)."
            )
        } else {
            lines.append("Recovery / readiness (from recent rides): \(recovery).")
        }
        if ctx.whoopLinked {
            lines.append(
                "Note: WHOOP’s public API does not include VO₂ max; use Apple Health in Mangox for VO₂ if available."
            )
        }
        if let hist = ctx.ftpHistory, !hist.isEmpty {
            lines.append("Recent FTP test trend (newest first): \(hist).")
        }
        if let plan = ctx.activePlanName {
            var p = "Active plan: \(plan)."
            if let prog = ctx.activePlanProgress { p += " Progress: \(prog)." }
            if let src = ctx.activePlanSource { p += " Source: \(src)." }
            p += " Adaptive ERG scale: \(ctx.adaptiveErgPercent)%."
            lines.append(p)
        } else {
            lines.append("No active plan in app.")
        }
        if let hint = ctx.planKeyDaySemanticsHint {
            lines.append("Plan week note: \(hint)")
        }
        if let goal = ctx.seasonGoalSummary, !goal.isEmpty {
            lines.append("Season goal: \(goal)")
        }
        if let ride = ctx.lastRide {
            lines.append("Last completed ride (\(ride.date)): \(ride.summary).")
        } else {
            lines.append("No completed ride on file.")
        }
        if let digest = ctx.recentRideDigest, !digest.isEmpty {
            lines.append("Recent ride history:\n\(digest)")
        }
        let joined = lines.joined(separator: "\n")
        if joined.count > 2800 {
            return String(joined.prefix(2800)) + "\n…"
        }
        return joined
    }

    /// Minimal rider context when the full fact sheet is too large for the on-device context window (TN3193).
    func coachFactSheetTextCompact(modelContext: ModelContext) -> String {
        let ctx = buildUserContext(modelContext: modelContext)
        let recovery = recoveryStatus(modelContext: modelContext)
        var lines: [String] = []
        lines.append(
            "Rider: FTP \(ctx.ftp)W, max HR \(ctx.maxHR), resting HR \(ctx.restingHR).")
        if ctx.whoopLinked, let pct = ctx.whoopRecoveryPercent {
            lines.append(
                "Week TSS: \(ctx.weekActualTss). WHOOP recovery \(Int(pct))%. Readiness: \(recovery)."
            )
        } else {
            lines.append(
                "Week TSS: \(ctx.weekActualTss). Workouts (30d): \(ctx.recentWorkoutsCount). Recovery: \(recovery)."
            )
        }
        if let hist = ctx.ftpHistory, !hist.isEmpty {
            lines.append("FTP tests: \(hist)")
        }
        if let plan = ctx.activePlanName {
            lines.append(
                "Plan: \(plan). \(ctx.activePlanProgress ?? "") ERG \(ctx.adaptiveErgPercent)%.")
        } else {
            lines.append("No active plan.")
        }
        if let ride = ctx.lastRide {
            lines.append("Last ride (\(ride.date)): \(ride.summary)")
        } else {
            lines.append("No last ride.")
        }
        if let digest = ctx.recentRideDigest, !digest.isEmpty {
            let firstLine = digest.split(separator: "\n").prefix(2).joined(separator: " | ")
            if !firstLine.isEmpty {
                lines.append("Recent rides: \(firstLine)")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Chooses full vs compact snapshot using `SystemLanguageModel.tokenCount` (budget ~1900 tokens for snapshot text alone).
    func coachTrainingSnapshotForOnDeviceNarrow(modelContext: ModelContext) async -> String {
        let full = coachFactSheetText(modelContext: modelContext)
        let compact = coachFactSheetTextCompact(modelContext: modelContext)
        let snapshotTokenBudget = 1900
        if #available(iOS 26.4, macOS 26.4, visionOS 26.4, *) {
            let model = SystemLanguageModel.default
            do {
                let fullTok = try await model.tokenCount(for: full)
                if fullTok <= snapshotTokenBudget {
                    MangoxFoundationModelsSupport.logSnapshotSelection(
                        fullChosen: true, tokenEstimate: fullTok)
                    return full
                }
                let compactTok = try await model.tokenCount(for: compact)
                MangoxFoundationModelsSupport.logSnapshotSelection(
                    fullChosen: false, tokenEstimate: compactTok)
                return compact
            } catch {
                return full.count > 2400 ? compact : full
            }
        }
        return full.count > 2400 ? compact : full
    }

    /// Quick starters + content-tagging topic chips for the empty coach state (sequential on MainActor).
    func loadCoachEmptyStartersContent(modelContext: ModelContext) async
        -> CoachEmptyStartersContent
    {
        let availability = starterPromptAvailability(modelContext: modelContext)
        let fallback = CoachEmptyStartersContent(
            prompts: contextualQuickPrompts(modelContext: modelContext),
            topicTags: []
        )
        guard OnDeviceCoachEngine.isSystemModelAvailable else { return fallback }

        let factSheet = coachFactSheetText(modelContext: modelContext)

        var topicTags: [String] = []
        if OnDeviceCoachEngine.isContentTaggingModelAvailable {
            topicTags =
                (try? await OnDeviceCoachEngine.generateStarterTopicTags(factSheet: factSheet))
                ?? []
        }

        let prompts: [QuickPrompt]
        do {
            let pack = try await OnDeviceCoachEngine.generateQuickPrompts(factSheet: factSheet)
            let sanitizedItems = OnDeviceCoachEngine.sanitizeQuickPromptItems(pack.items).map {
                QuickPrompt(text: $0.text, icon: $0.icon)
            }
            let sanitized = groundedQuickPrompts(
                from: sanitizedItems,
                availability: availability,
                fallback: contextualQuickPrompts(modelContext: modelContext)
            )
            if sanitized.count >= 2 {
                prompts = sanitized
            } else {
                prompts = contextualQuickPrompts(modelContext: modelContext)
            }
        } catch {
            prompts = contextualQuickPrompts(modelContext: modelContext)
        }

        return CoachEmptyStartersContent(prompts: prompts, topicTags: topicTags)
    }

    // MARK: - On-device narrow tool payloads

    /// Multi-line digest for `mangox_recent_workouts` (newest first).
    func coachWorkoutHistoryDigestForOnDeviceTools(modelContext: ModelContext, limit: Int = 20)
        -> String
    {
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { $0.statusRaw == "completed" },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        let rides =
            ((try? modelContext.fetch(descriptor)) ?? [])
            .filter(\.isValid)
            .prefix(limit)

        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none

        if rides.isEmpty { return "No completed rides on file." }

        return rides.map { ride in
            var line =
                "\(df.string(from: ride.startDate)): TSS \(Int(ride.tss)), \(Int(ride.duration / 60))min"
            if ride.avgPower > 0 {
                line += ", \(Int(ride.avgPower))W avg"
            }
            if !ride.notes.isEmpty {
                line += " — notes: \(ride.notes.prefix(140))"
            }
            if let r = ride.savedRouteName, !r.isEmpty {
                line += " — route: \(r)"
            }
            return line
        }.joined(separator: "\n")
    }

    func coachRiderExtendedProfileToolPayload(modelContext: ModelContext) -> String {
        let ctx = buildUserContext(modelContext: modelContext)
        var lines: [String] = []
        if let w = ctx.riderWeightKg, w > 0 {
            lines.append(String(format: "Weight: %.1f kg", w))
        }
        if let a = ctx.riderAge, a > 0 {
            lines.append("Age: \(a) years")
        }
        if let g = ctx.seasonGoalSummary, !g.isEmpty {
            lines.append("Season goal: \(g)")
        }
        if let h = ctx.planKeyDaySemanticsHint, !h.isEmpty {
            lines.append("Plan week semantics: \(h)")
        }
        return lines.isEmpty
            ? "No extended rider profile fields stored in Mangox." : lines.joined(separator: "\n")
    }

    func coachFTPTestHistoryToolPayload(limit: Int = 10) -> String {
        let rows =
            FTPTestHistory.load()
            .sorted { $0.date > $1.date }
            .prefix(limit)
        if rows.isEmpty { return "No FTP test history stored." }
        let df = DateFormatter()
        df.dateStyle = .medium
        return rows.map { r in
            let applied = r.applied ? "applied" : "not applied"
            return "\(df.string(from: r.date)): \(r.estimatedFTP)W est (\(applied))"
        }.joined(separator: "\n")
    }

    func coachWhoopRecoveryToolPayload(modelContext: ModelContext) -> String {
        let ctx = buildUserContext(modelContext: modelContext)
        guard ctx.whoopLinked else { return "No WHOOP account connected." }

        var lines = ["WHOOP connected."]
        if let pct = ctx.whoopRecoveryPercent {
            lines.append("Recovery: \(Int(pct))%")
        }
        if let rhr = ctx.whoopRestingHR {
            lines.append("Resting HR: \(rhr) bpm")
        }
        if let hrv = ctx.whoopHrvMs {
            lines.append("HRV: \(hrv) ms")
        }
        if let maxHR = ctx.whoopMaxHeartRate {
            lines.append("Profile max HR: \(maxHR) bpm")
        }
        return lines.joined(separator: "\n")
    }

    func coachActivePlanContextToolPayload(modelContext: ModelContext) -> String {
        let ctx = buildUserContext(modelContext: modelContext)
        var lines: [String] = []
        if let plan = ctx.activePlanName, !plan.isEmpty {
            lines.append("Active plan: \(plan)")
            if let progress = ctx.activePlanProgress, !progress.isEmpty {
                lines.append("Progress: \(progress)")
            }
            lines.append("Adaptive ERG: \(ctx.adaptiveErgPercent)%")
        } else {
            lines.append("No active plan in app.")
        }
        lines.append("Current week TSS: \(ctx.weekActualTss)")
        if let goal = ctx.seasonGoalSummary, !goal.isEmpty {
            lines.append("Season goal: \(goal)")
        }
        if let hint = ctx.planKeyDaySemanticsHint, !hint.isEmpty {
            lines.append("Plan note: \(hint)")
        }
        return lines.joined(separator: "\n")
    }

    func starterPromptAvailability(modelContext: ModelContext) -> CoachStarterPromptAvailability {
        let ctx = buildUserContext(modelContext: modelContext)
        return CoachStarterPromptAvailability(
            hasRecentRide: ctx.lastRide != nil,
            hasAnyRideData: ctx.recentWorkoutsCount > 0 || ctx.lastRide != nil,
            hasFTPHistory: !(ctx.ftpHistory?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true),
            hasActivePlan: !(ctx.activePlanName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true),
            hasWhoopRecovery: ctx.whoopLinked && ctx.whoopRecoveryPercent != nil
        )
    }

    func groundedQuickPrompts(
        from candidates: [QuickPromptItem],
        availability: CoachStarterPromptAvailability,
        fallback: [QuickPrompt]
    ) -> [QuickPrompt] {
        groundedQuickPrompts(
            from: candidates.map { QuickPrompt(text: $0.text, icon: $0.icon) },
            availability: availability,
            fallback: fallback
        )
    }

    func groundedQuickPrompts(
        from candidates: [QuickPrompt],
        availability: CoachStarterPromptAvailability,
        fallback: [QuickPrompt]
    ) -> [QuickPrompt] {
        var grounded: [QuickPrompt] = []
        var seen = Set<String>()

        func appendIfAllowed(_ prompt: QuickPrompt) {
            let trimmed = prompt.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let normalized = trimmed.lowercased()
            guard !seen.contains(normalized) else { return }
            guard starterPromptIsSupported(normalized, availability: availability) else { return }
            seen.insert(normalized)
            grounded.append(QuickPrompt(text: trimmed, icon: prompt.icon))
        }

        candidates.forEach(appendIfAllowed)
        fallback.forEach(appendIfAllowed)
        return Array(grounded.prefix(4))
    }

    func starterPromptIsSupported(
        _ normalizedPrompt: String,
        availability: CoachStarterPromptAvailability
    ) -> Bool {
        let mentionsWhoop =
            normalizedPrompt.contains("whoop") || normalizedPrompt.contains("recovery")
            || normalizedPrompt.contains("hrv")
        if mentionsWhoop, !availability.hasWhoopRecovery { return false }

        let mentionsPlan =
            normalizedPrompt.contains("plan") || normalizedPrompt.contains("workout today")
            || normalizedPrompt.contains("today's workout")
            || normalizedPrompt.contains("todays workout")
            || normalizedPrompt.contains("training load")
        if mentionsPlan, !availability.hasActivePlan { return false }

        let mentionsRide =
            normalizedPrompt.contains("last ride") || normalizedPrompt.contains("recent ride")
            || normalizedPrompt.contains("my ride") || normalizedPrompt.contains("how hard was")
        if mentionsRide, !availability.hasRecentRide { return false }

        let mentionsFTPHistory =
            normalizedPrompt.contains("ftp trend") || normalizedPrompt.contains("last ftp")
            || normalizedPrompt.contains("ftp test")
        if mentionsFTPHistory, !availability.hasFTPHistory { return false }

        if normalizedPrompt.contains("ftp"), !availability.hasFTPHistory,
            !normalizedPrompt.contains("power zone"), !normalizedPrompt.contains("power zones")
        {
            return false
        }

        if !availability.hasAnyRideData,
            normalizedPrompt.contains("training load")
                || normalizedPrompt.contains("how tired")
                || normalizedPrompt.contains("recovery today")
        {
            return false
        }

        return true
    }

    static func generateSingleWorkoutDraft(
        userMessage: String,
        trainingSnapshot: String,
        ftp: Int
    ) async throws -> GeneratedWorkout {
        try MangoxFoundationModelsSupport.throwIfLocaleUnsupported()

        let instructions = """
            Generate one structured indoor cycling workout for Mangox.
            Use the rider snapshot as ground truth. Do not invent missing metrics.
            Keep the workout realistic for the requested duration. Include warm-up and cool-down when appropriate.
            Use simple zone labels like Z1, Z2, Z3, Z4, Z5, Mixed.
            """
        let model = MangoxFoundationModelsSupport.coachSystemLanguageModel()
        let session = LanguageModelSession(
            model: model,
            tools: [],
            instructions: Instructions(instructions)
        )
        let prompt = """
            Rider snapshot:
            \(trainingSnapshot)

            Current FTP:
            \(ftp) W

            User request:
            \(userMessage)
            """

        let response = try await session.respond(
            to: prompt,
            generating: OnDeviceGeneratedWorkout.self,
            options: GenerationOptions(sampling: .greedy)
        )
        let generated = response.content
        let intervals = generated.intervals.enumerated().map { index, item in
            IntervalSegment(
                order: index + 1,
                name: item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Interval \(index + 1)" : item.name,
                durationSeconds: max(30, item.durationSeconds),
                zone: Self.trainingZoneTarget(from: item.zone),
                repeats: max(1, item.repeats),
                cadenceLow: item.cadenceLow,
                cadenceHigh: item.cadenceHigh,
                recoverySeconds: max(0, item.recoverySeconds),
                recoveryZone: Self.trainingZoneTarget(from: item.recoveryZone),
                notes: item.notes,
                suggestedTrainerMode: Self.trainerMode(from: item.suggestedTrainerMode),
                simulationGrade: item.simulationGrade
            )
        }
        let day = PlanDay(
            id: "single-workout",
            weekNumber: 0,
            dayOfWeek: 1,
            dayType: .workout,
            title: generated.title,
            durationMinutes: max(15, generated.durationMinutes),
            zone: Self.trainingZoneTarget(from: generated.zone),
            notes: generated.notes,
            intervals: intervals,
            isKeyWorkout: true,
            requiresFTPTest: false
        )
        return GeneratedWorkout(
            title: generated.title,
            purpose: generated.purpose,
            rationale: generated.rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil : generated.rationale,
            day: day
        )
    }

    private static func trainingZoneTarget(from raw: String) -> TrainingZoneTarget {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "Z1": return .z1
        case "Z2": return .z2
        case "Z3": return .z3
        case "Z4": return .z4
        case "Z5": return .z5
        case "Z1-Z2": return .z1z2
        case "Z2-Z3": return .z2z3
        case "Z3-Z4": return .z3z4
        case "Z3-Z5": return .z3z5
        case "Z4-Z5": return .z4z5
        case "REST": return .rest
        default: return .mixed
        }
    }

    private static func trainerMode(from raw: String) -> SuggestedTrainerMode {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "simulation", "sim": return .simulation
        case "free", "free ride", "free_ride", "freeride": return .freeRide
        default: return .erg
        }
    }
}
