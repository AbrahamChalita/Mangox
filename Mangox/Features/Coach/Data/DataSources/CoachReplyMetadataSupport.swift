import Foundation
import FoundationModels

// MARK: - Category / tags / references for FM + cloud coach replies

enum CoachReplyMetadataSupport {

    nonisolated static let allowedCategories: Set<String> = [
        "training_advice",
        "plan_analysis",
        "recovery",
        "nutrition",
        "equipment",
        "clarification",
    ]

  /// Normalizes model-supplied category; `deliveryFallback` wins when the model omits or sends junk.
    static func resolvedCategory(modelCategory: String?, deliveryFallback: String) -> String {
        let normalized = normalizeCategoryToken(modelCategory)
        if let normalized, allowedCategories.contains(normalized) || isDeliveryCategory(normalized) {
            return normalized
        }
        return deliveryFallback
    }

    static func resolvedTags(
        modelTags: [String],
        modelCategory: String? = nil,
        body: String,
        usedWebSearch: Bool,
        planIntake: Bool
    ) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        if let cat = normalizeCategoryToken(modelCategory), allowedCategories.contains(cat) {
            seen.insert(cat)
            ordered.append(cat)
        }
        for raw in modelTags {
            let tag = normalizeTag(raw)
            guard !tag.isEmpty, seen.insert(tag).inserted else { continue }
            ordered.append(tag)
        }
        for inferred in inferredTags(body: body, usedWebSearch: usedWebSearch, planIntake: planIntake) {
            guard seen.insert(inferred).inserted else { continue }
            ordered.append(inferred)
        }
        return Array(ordered.prefix(4))
    }

    /// True when the model only promises to search without listing grounded results.
    nonisolated static func isWebSearchDeferralOnly(_ body: String) -> Bool {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let lower = trimmed.lowercased()
        let deferralPhrases = [
            "let me search", "i'll search", "i will search", "let me look",
            "i'll look", "i will look", "searching for", "looking up",
            "give me a moment", "let me find", "i'll find", "i will find",
        ]
        guard deferralPhrases.contains(where: { lower.contains($0) }) else { return false }
        let substantiveSignals = [
            "http", "•", "\n-", "\n*", "2024", "2025", "2026", "2027",
            "january", "february", "march", "april", "may", "june",
            "july", "august", "september", "october", "november", "december",
        ]
        return !substantiveSignals.contains(where: { lower.contains($0) })
    }

    static func thinkingSteps(from reasoning: String) -> [String] {
        let trimmed = reasoning.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return [String(trimmed.prefix(320))]
    }

    /// Best-effort web references from PCC / FM transcript (URLs + segment dumps).
    static func referencesFromTranscript(_ session: LanguageModelSession?) -> [ChatReference] {
        guard let session else { return [] }
        let chunks = session.transcript.map { String(describing: $0) }
        return referencesFromTranscriptText(chunks.joined(separator: "\n"))
    }

    static func referencesFromTranscriptText(_ text: String) -> [ChatReference] {
        guard !text.isEmpty else { return [] }
        let pattern = #"https?:\/\/[^\s\]\)\"'<>]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var seen = Set<String>()
        var refs: [ChatReference] = []
        for match in matches {
            var url = ns.substring(with: match.range)
            while let last = url.last, ",.;)".contains(last) { url.removeLast() }
            guard !url.isEmpty, seen.insert(url).inserted else { continue }
            let title = referenceTitle(for: url, in: text)
            refs.append(ChatReference(title: title, url: url, snippet: nil))
            if refs.count >= 8 { break }
        }
        return refs
    }

    // MARK: - Private

    private static func isDeliveryCategory(_ cat: String) -> Bool {
        switch cat {
        case "on_device", "on_device_coach", "pcc_coach", "pcc_web_search", "plan_intake":
            return true
        default:
            return false
        }
    }

    private static func normalizeCategoryToken(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: " ", with: "_")
        return token.isEmpty ? nil : token
    }

    private static func normalizeTag(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: " ", with: "_")
    }

    private static func inferredTags(body: String, usedWebSearch: Bool, planIntake: Bool) -> [String] {
        let lower = body.lowercased()
        var tags: [String] = []
        func add(_ tag: String, if condition: Bool) {
            if condition { tags.append(tag) }
        }
        add("ftp", if: lower.contains("ftp") || lower.contains("functional threshold"))
        add("tss", if: lower.contains("tss") || lower.contains("training stress"))
        add("recovery", if: lower.contains("recovery") || lower.contains("whoop") || lower.contains("hrv"))
        add("power", if: lower.contains("watts") || lower.contains("normalized power") || lower.contains(" np "))
        add("plan", if: planIntake || lower.contains("training plan") || lower.contains("mesocycle"))
        add("periodization", if: lower.contains("periodization") || lower.contains("block"))
        add("nutrition", if: lower.contains("nutrition") || lower.contains("fuel"))
        add("web_search", if: usedWebSearch)
        return tags
    }

    private static func referenceTitle(for url: String, in context: String) -> String {
        if let host = URL(string: url)?.host?.replacingOccurrences(of: "www.", with: ""), !host.isEmpty {
            return host
        }
        if let range = context.range(of: url) {
            let before = context[..<range.lowerBound]
            if let match = before.range(of: #"title[:\s]+([^\n]{4,80})"#, options: .regularExpression) {
                let fragment = String(before[match])
                let title = fragment.replacingOccurrences(of: #"^title[:\s]+"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty { return title }
            }
        }
        return "Web source"
    }
}
