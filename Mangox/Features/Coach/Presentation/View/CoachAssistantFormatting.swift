import Foundation
import SwiftUI

/// Normalizes model-supplied `content` for coach bubbles: list markers, Markdown, metrics, and stray emphasis asterisks.
enum CoachAssistantFormatting {

    /// Rich text for the final assistant bubble (after thinking tags are stripped by the caller).
    static func attributedContent(from raw: String, category: String? = nil) -> AttributedString {
        let highlight = category?.lowercased() != "pcc_web_search"
        return attributedContentForStreaming(from: raw, highlightMetrics: highlight)
    }

    /// Memoized variant for committed bubbles: markdown parsing + metric regex run once per
    /// message instead of on every transcript invalidation.
    static func cachedAttributedContent(from raw: String, category: String? = nil) -> AttributedString {
        let key = "\(category ?? "")\u{1F}\(raw)" as NSString
        if let hit = attributedContentCache.object(forKey: key) {
            return hit.value
        }
        let value = attributedContent(from: raw, category: category)
        attributedContentCache.setObject(AttributedStringBox(value), forKey: key)
        return value
    }

    private final class AttributedStringBox {
        let value: AttributedString
        init(_ value: AttributedString) { self.value = value }
    }

    private static let attributedContentCache: NSCache<NSString, AttributedStringBox> = {
        let cache = NSCache<NSString, AttributedStringBox>()
        cache.countLimit = 256
        return cache
    }()

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

    /// Memoized variant for the pending reply bubble so each token is normalized once
    /// even if the view body is evaluated multiple times during streaming.
    static func cachedPlainTextForStreaming(_ raw: String) -> String {
        let key = raw as NSString
        if let hit = streamingPlainTextCache.object(forKey: key) { return hit as String }
        let value = plainTextForStreaming(raw)
        streamingPlainTextCache.setObject(value as NSString, forKey: key)
        return value
    }

    private static let streamingPlainTextCache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 256
        return cache
    }()

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
        
        let plainString = String(attr.characters)
        let nsString = plainString as NSString
        var result = attr
        
        for match in regex.matches(in: plainString, range: NSRange(location: 0, length: nsString.length)) {
            guard let swiftRange = Range(match.range, in: plainString) else { continue }
            
            // Map character offsets from plainString to result indices safely
            let startOffset = plainString.distance(from: plainString.startIndex, to: swiftRange.lowerBound)
            let endOffset = plainString.distance(from: plainString.startIndex, to: swiftRange.upperBound)
            
            let startIdx = result.characters.index(result.startIndex, offsetBy: startOffset)
            let endIdx = result.characters.index(result.startIndex, offsetBy: endOffset)
            
            // Avoid override or double emphasis if metric is already bold in markdown
            let sub = result[startIdx..<endIdx]
            let isAlreadyBold = sub.runs.contains { run in
                if let intent = run.inlinePresentationIntent {
                    return intent.contains(.stronglyEmphasized)
                }
                return false
            }
            if isAlreadyBold { continue }
            
            var container = AttributeContainer()
            container.foregroundColor = Color.orange.opacity(0.95)
            container.inlinePresentationIntent = .stronglyEmphasized
            result[startIdx..<endIdx].mergeAttributes(container)
        }
        return result
    }
}
