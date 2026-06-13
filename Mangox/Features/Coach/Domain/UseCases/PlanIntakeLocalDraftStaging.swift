// Features/Coach/Domain/UseCases/PlanIntakeLocalDraftStaging.swift
import Foundation

/// Stages `PlanGenerationDraft` after on-device / PCC plan intake when required fields
/// are present in the transcript — mirrors cloud `generate_plan` tool staging.
enum PlanIntakeLocalDraftStaging {
    struct TurnContext: Sendable {
        let body: String
        let followUp: String
        let suggestedActionLabels: [String]
        let category: String
        let followUpBlocksCount: Int
    }

    /// Returns draft inputs when the assistant turn signals plan confirmation readiness.
    static func draftIfReady(
        messages: [ChatMessage],
        turn: TurnContext,
        ftp: Int
    ) -> PlanGenerationDraft? {
        guard turn.followUpBlocksCount == 0 else { return nil }
        guard isReadyToStage(turn: turn, messages: messages) else { return nil }
        guard let inputs = extractPlanInputs(from: messages, ftp: ftp) else { return nil }
        return PlanGenerationDraft(
            inputs: inputs,
            summaryLine: AIService.planSummaryLine(for: inputs)
        )
    }

    // MARK: - Readiness

    private static func isReadyToStage(turn: TurnContext, messages: [ChatMessage]) -> Bool {
        let followUp = turn.followUp.trimmingCharacters(in: .whitespacesAndNewlines)
        if !followUp.isEmpty { return false }

        if userExplicitlyRequestedGeneration(messages: messages) { return true }

        let bodyLower = turn.body.lowercased()
        let readinessPhrases = [
            "ready to generate",
            "generate your plan",
            "create your plan",
            "build your plan",
            "confirm these details",
            "looks good to me",
            "i've got what i need",
            "i have what i need",
            "tap generate",
            "when you're ready to generate",
        ]
        if readinessPhrases.contains(where: { bodyLower.contains($0) }) { return true }

        let generateChipLabels = turn.suggestedActionLabels.map { $0.lowercased() }
        if generateChipLabels.contains(where: {
            $0.contains("generate") && ($0.contains("plan") || $0.contains("yes"))
        }) {
            return true
        }

        let cat = turn.category.lowercased()
        if cat == "plan_analysis", extractPlanInputs(from: messages, ftp: 0) != nil {
            return bodyLower.contains("confirm") || bodyLower.contains("summary")
        }

        return false
    }

    private static func userExplicitlyRequestedGeneration(messages: [ChatMessage]) -> Bool {
        guard let lastUser = messages.last(where: { $0.role == .user })?.content else { return false }
        let lower = lastUser.lowercased()
        let markers = [
            "generate now", "go ahead", "create the plan", "generate the plan",
            "generate my plan", "yes — generate", "yes, generate", "just generate",
            "skip optional", "defaults are fine",
        ]
        return markers.contains(where: { lower.contains($0) })
    }

    // MARK: - Extraction

    private static func extractPlanInputs(from messages: [ChatMessage], ftp: Int) -> PlanInputs? {
        let transcript = messages.map(\.content).joined(separator: "\n")
        guard let eventDate = extractEventDate(from: transcript) else { return nil }
        guard let eventName = extractEventName(from: messages, transcript: transcript) else { return nil }

        return PlanInputs(
            event_name: eventName,
            event_date: eventDate,
            ftp: max(ftp, 1),
            weekly_hours: extractWeeklyHours(from: transcript),
            experience: extractExperience(from: transcript),
            route_option: extractRouteOption(from: transcript),
            target_distance_km: extractDistanceKm(from: transcript),
            target_elevation_m: extractElevationM(from: transcript),
            event_location: extractEventLocation(from: transcript),
            event_notes: nil
        )
    }

    private static func extractEventDate(from transcript: String) -> String? {
        let pattern = #"\b(20\d{2}-\d{2}-\d{2})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(transcript.startIndex..<transcript.endIndex, in: transcript)
        let matches = regex.matches(in: transcript, range: range)
        for match in matches.reversed() {
            guard let r = Range(match.range(at: 1), in: transcript) else { continue }
            let candidate = String(transcript[r])
            if AIService.normalizeEventDateForPlan(candidate) != nil {
                return candidate
            }
        }
        return nil
    }

    private static func extractEventName(from messages: [ChatMessage], transcript: String) -> String? {
        if let fromBatch = parseEventNameFromBatchAnswers(messages) { return fromBatch }

        let eventPatterns = [
            #"(?i)(?:event|race|goal|training for)[:\s—–-]+(.{3,80})"#,
            #"(?i)(?:gran fondo|sportive|criterium|century|granfondo|l\.?etape|marathon)\s+([^\n,.]{3,60})"#,
        ]
        for pattern in eventPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
                let match = regex.firstMatch(
                    in: transcript,
                    range: NSRange(transcript.startIndex..<transcript.endIndex, in: transcript)
                ),
                match.numberOfRanges > 1,
                let r = Range(match.range(at: 1), in: transcript)
            {
                let name = String(transcript[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                if name.count >= 3 { return cleanEventName(name) }
            }
        }

        if let userSeed = messages.first(where: {
            $0.role == .user && AIService.shouldForcePlanIntake(for: $0.content)
        })?.content {
            let trimmed = userSeed.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count > 12, trimmed.count < 120 { return cleanEventName(trimmed) }
        }

        return nil
    }

    private static func parseEventNameFromBatchAnswers(_ messages: [ChatMessage]) -> String? {
        guard let batch = messages.last(where: {
            $0.role == .user && $0.content.lowercased().hasPrefix("here are my answers:")
        })?.content else { return nil }

        for line in batch.components(separatedBy: "\n") {
            let lower = line.lowercased()
            guard lower.contains("event") || lower.contains("race") || lower.contains("goal") else {
                continue
            }
            if let dash = line.range(of: "—") ?? line.range(of: " - ") {
                let answer = String(line[dash.upperBound...]).trimmingCharacters(in: .whitespaces)
                if answer.count >= 3 { return cleanEventName(answer) }
            }
            if let colon = line.firstIndex(of: ":") {
                let answer = String(line[line.index(after: colon)...])
                    .trimmingCharacters(in: .whitespaces)
                if answer.count >= 3 { return cleanEventName(answer) }
            }
        }
        return nil
    }

    private static func cleanEventName(_ raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.hasPrefix("•") { name = String(name.dropFirst()).trimmingCharacters(in: .whitespaces) }
        if name.count > 80 { name = String(name.prefix(80)) }
        return name
    }

    private static func extractWeeklyHours(from transcript: String) -> Int? {
        let patterns = [
            #"(?i)(\d+)\s*(?:-|–|to)\s*(\d+)\s*hours?\s*(?:per|\/)\s*week"#,
            #"(?i)(\d+)\s*hours?\s*(?:per|\/)\s*week"#,
            #"(?i)weekly hours?[:\s—–-]+(\d+)"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                let match = regex.firstMatch(
                    in: transcript,
                    range: NSRange(transcript.startIndex..<transcript.endIndex, in: transcript)
                ),
                match.numberOfRanges > 1,
                let r = Range(match.range(at: 1), in: transcript),
                let value = Int(transcript[r])
            else { continue }
            if match.numberOfRanges > 2,
                let r2 = Range(match.range(at: 2), in: transcript),
                let high = Int(transcript[r2])
            {
                return (value + high) / 2
            }
            return value
        }
        return nil
    }

    private static func extractExperience(from transcript: String) -> String? {
        let lower = transcript.lowercased()
        if lower.contains("beginner") { return "beginner" }
        if lower.contains("intermediate") { return "intermediate" }
        if lower.contains("advanced") { return "advanced" }
        return nil
    }

    private static func extractRouteOption(from transcript: String) -> String? {
        let lower = transcript.lowercased()
        for option in ["long", "medium", "short"] {
            if lower.contains("route: \(option)") || lower.contains("route — \(option)") {
                return option
            }
        }
        return nil
    }

    private static func extractDistanceKm(from transcript: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: #"(?i)(\d+(?:\.\d+)?)\s*km"#),
            let match = regex.firstMatch(
                in: transcript,
                range: NSRange(transcript.startIndex..<transcript.endIndex, in: transcript)
            ),
            let r = Range(match.range(at: 1), in: transcript),
            let value = Double(transcript[r])
        else { return nil }
        return value
    }

    private static func extractElevationM(from transcript: String) -> Double? {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)(\d+(?:\.\d+)?)\s*m(?:\s|$| climbing)"#
        ),
            let match = regex.firstMatch(
                in: transcript,
                range: NSRange(transcript.startIndex..<transcript.endIndex, in: transcript)
            ),
            let r = Range(match.range(at: 1), in: transcript),
            let value = Double(transcript[r])
        else { return nil }
        return value
    }

    private static func extractEventLocation(from transcript: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"(?i)location[:\s—–-]+([^\n]{3,60})"#),
            let match = regex.firstMatch(
                in: transcript,
                range: NSRange(transcript.startIndex..<transcript.endIndex, in: transcript)
            ),
            let r = Range(match.range(at: 1), in: transcript)
        else { return nil }
        return String(transcript[r]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
