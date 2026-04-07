import Foundation

/// Normalizes model-supplied `content` for coach bubbles: list markers, Markdown, and stray emphasis asterisks.
enum CoachAssistantFormatting {

    /// Rich text for the final assistant bubble (after thinking tags are stripped by the caller).
    static func attributedContent(from raw: String) -> AttributedString {
        let normalized = normalizeLeadingAsteriskBullets(raw)
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        if let parsed = try? AttributedString(markdown: normalized, options: options) {
            return parsed
        }
        return AttributedString(plainFallback(normalized))
    }

    /// Streaming buffer: avoid broken partial Markdown; normalize bullets and drop obvious `**` / `*` wrappers.
    static func plainTextForStreaming(_ raw: String) -> String {
        plainFallback(normalizeLeadingAsteriskBullets(raw))
    }

    // MARK: - Private

    /// Models often emit `* item` lists; `inlineOnly` Markdown ignored those. Map to `- item` for full Markdown lists.
    private static func normalizeLeadingAsteriskBullets(_ s: String) -> String {
        let lines = s.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.map { lineSub -> String in
            let line = String(lineSub)
            guard let range = line.range(of: #"^\s*\*\s+"#, options: .regularExpression) else {
                return line
            }
            return line.replacingCharacters(in: range, with: "- ")
        }.joined(separator: "\n")
    }

    private static func plainFallback(_ s: String) -> String {
        var t = s
        t = t.replacingOccurrences(
            of: #"\*\*([^*]+)\*\*"#,
            with: "$1",
            options: .regularExpression
        )
        t = t.replacingOccurrences(
            of: #"(?<!\*)\*([^*\n]+)\*(?!\*)"#,
            with: "$1",
            options: .regularExpression
        )
        return t
    }
}
