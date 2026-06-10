import Foundation
import SwiftUI

/// Normalizes model-supplied `content` for coach bubbles: list markers, Markdown, metrics, and stray emphasis asterisks.
enum CoachAssistantFormatting {

    /// Rich text for the final assistant bubble (after thinking tags are stripped by the caller).
    static func attributedContent(from raw: String, category: String? = nil) -> AttributedString {
        let highlight = category?.lowercased() != "pcc_web_search"
        return attributedContentForStreaming(from: raw, highlightMetrics: highlight)
    }

    /// Streaming / in-progress text — same markdown path as the final bubble, without metric tinting.
    static func attributedContentForStreaming(from raw: String, highlightMetrics: Bool = false) -> AttributedString {
        let normalized = normalizeLeadingAsteriskBullets(sanitizePartialMarkdown(raw))
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        var result: AttributedString
        if let parsed = try? AttributedString(markdown: normalized, options: options) {
            result = parsed
        } else {
            result = AttributedString(plainFallback(normalized))
        }
        if highlightMetrics {
            result = applyMetricHighlighting(to: result, source: normalized)
        }
        return result
    }

    /// Streaming buffer fallback when attributed rendering is too heavy (accessibility, very long drafts).
    static func plainTextForStreaming(_ raw: String) -> String {
        plainFallback(normalizeLeadingAsteriskBullets(sanitizePartialMarkdown(raw)))
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

    /// Close dangling `**` while tokens are still arriving so bold does not flicker away mid-stream.
    private static func sanitizePartialMarkdown(_ s: String) -> String {
        guard !s.isEmpty else { return s }
        var t = s
        let markerCount = t.components(separatedBy: "**").count - 1
        if markerCount % 2 == 1 {
            t += "**"
        }
        return t
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

    private static func applyMetricHighlighting(to attr: AttributedString, source: String) -> AttributedString {
        let pattern =
            #"\b(?:FTP\s*\d+(?:\.\d+)?|\d+(?:\.\d+)?\s*(?:W|TSS|tss|bpm|BPM))\b|\b\d+(?:\.\d+)?\s*%\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return attr }
        let boldRanges = markdownBoldRanges(in: source)
        var result = attr
        let ns = source as NSString
        for match in regex.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
            guard let swiftRange = Range(match.range, in: source) else { continue }
            if overlapsMarkdownBold(swiftRange, boldRanges: boldRanges) { continue }
            guard let start = AttributedString.Index(swiftRange.lowerBound, within: result),
                  let end = AttributedString.Index(swiftRange.upperBound, within: result)
            else { continue }
            var container = AttributeContainer()
            container.foregroundColor = Color.orange.opacity(0.95)
            container.inlinePresentationIntent = .stronglyEmphasized
            result[start..<end].mergeAttributes(container)
        }
        return result
    }

    private static func markdownBoldRanges(in source: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var searchStart = source.startIndex
        while searchStart < source.endIndex {
            guard let open = source.range(of: "**", range: searchStart..<source.endIndex) else { break }
            let afterOpen = open.upperBound
            guard let close = source.range(of: "**", range: afterOpen..<source.endIndex) else { break }
            ranges.append(open.lowerBound..<close.upperBound)
            searchStart = close.upperBound
        }
        return ranges
    }

    private static func overlapsMarkdownBold(
        _ range: Range<String.Index>,
        boldRanges: [Range<String.Index>]
    ) -> Bool {
        boldRanges.contains { bold in
            range.lowerBound < bold.upperBound && range.upperBound > bold.lowerBound
        }
    }
}
