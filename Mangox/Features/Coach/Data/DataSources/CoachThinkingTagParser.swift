import Foundation

/// Parses common model "thinking" / reasoning wrappers out of streamed or final text so the UI can
/// show the answer cleanly and optionally surface reasoning in a separate control.
///
/// Supports `<thinking>…</thinking>`, `<reasoning>`, `<thought>`, `<redacted_thinking>`, and
/// attribute forms such as `<thinking type="…">` (anything through the first `>`).
enum CoachThinkingTagParser {

    struct StreamSnapshot: Sendable {
        /// Text safe to show as the main assistant reply (tags and their inner reasoning removed).
        var visible: String
        /// Finished reasoning blocks, in order (one entry per closed tag region).
        var completedBlocks: [String]
        /// Reasoning text inside an **unclosed** tag at the end of the buffer (streaming).
        var openDraft: String?
    }

    /// Incremental parse of everything received on the wire so far.
    static func snapshot(streamBuffer: String) -> StreamSnapshot {
        parseEntire(streamBuffer, treatTrailingOpenAsDraft: true)
    }

    /// Final pass on persisted / JSON `content` before storing or displaying in history.
    static func finalizedContent(_ raw: String) -> (visible: String, extraThinkingBlocks: [String]) {
        let snap = parseEntire(raw, treatTrailingOpenAsDraft: false)
        let extra = snap.completedBlocks + (snap.openDraft.map { [$0] } ?? [])
        let visTrim = snap.visible.trimmingCharacters(in: .whitespacesAndNewlines)
        if visTrim.isEmpty, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return (raw, extra)
        }
        return (snap.visible, extra)
    }

    // MARK: - Core parse

    private static let closeByOpenPrefix: [(openPrefix: String, close: String)] = [
        ("<thinking", "</thinking>"),
        ("<reasoning", "</reasoning>"),
        ("<thought", "</thought>"),
        ("<redacted_thinking", "</redacted_thinking>")
    ]

    private static func parseEntire(_ raw: String, treatTrailingOpenAsDraft: Bool) -> StreamSnapshot {
        var visible = ""
        var blocks: [String] = []
        var i = raw.startIndex

        while i < raw.endIndex {
            guard let lt = raw[i...].firstIndex(of: "<") else {
                visible.append(contentsOf: raw[i..<raw.endIndex])
                break
            }
            visible.append(contentsOf: raw[i..<lt])

            let tail = raw[lt...]
            if incompleteOpenPrefix(tail) {
                return StreamSnapshot(visible: visible, completedBlocks: blocks, openDraft: nil)
            }

            guard let match = matchOpenTag(tail) else {
                visible.append("<")
                i = raw.index(after: lt)
                continue
            }

            let openEnd = raw.index(lt, offsetBy: match.openLength)
            guard openEnd <= raw.endIndex else { break }

            if let closeRange = raw[openEnd...].range(of: match.closeTag, options: .caseInsensitive) {
                let inner = String(raw[openEnd..<closeRange.lowerBound])
                if let trimmed = normalizedBlock(inner) {
                    blocks.append(trimmed)
                }
                i = closeRange.upperBound
            } else {
                let inner = String(raw[openEnd..<raw.endIndex])
                if treatTrailingOpenAsDraft {
                    let draft = normalizedBlock(inner)
                    return StreamSnapshot(
                        visible: visible,
                        completedBlocks: blocks,
                        openDraft: (draft?.isEmpty ?? true) ? "…" : draft
                    )
                }
                if let trimmed = normalizedBlock(inner) {
                    blocks.append(trimmed)
                }
                break
            }
        }

        return StreamSnapshot(visible: visible, completedBlocks: blocks, openDraft: nil)
    }

    private struct OpenTagMatch {
        let openLength: Int
        let closeTag: String
    }

    private static func matchOpenTag(_ s: Substring) -> OpenTagMatch? {
        guard s.first == "<" else { return nil }
        for pair in closeByOpenPrefix {
            let prefix = pair.openPrefix
            guard s.count >= prefix.count else { continue }
            let headEnd = s.index(s.startIndex, offsetBy: prefix.count)
            let head = s[s.startIndex..<headEnd]
            guard String(head).caseInsensitiveCompare(prefix) == .orderedSame else { continue }

            var scan = headEnd
            while scan < s.endIndex {
                if s[scan] == ">" {
                    let afterGt = s.index(after: scan)
                    let len = s.distance(from: s.startIndex, to: afterGt)
                    return OpenTagMatch(openLength: len, closeTag: pair.close)
                }
                scan = s.index(after: scan)
            }
            return nil
        }
        return nil
    }

    /// `>` not yet received while the tail still matches a known open tag (including full `<thinking` with no `>`).
    private static func incompleteOpenPrefix(_ s: Substring) -> Bool {
        guard s.first == "<", !s.contains(">") else { return false }
        let frag = String(s).lowercased()
        for pair in closeByOpenPrefix {
            let o = pair.openPrefix.lowercased()
            if o.hasPrefix(frag) { return true }
        }
        return false
    }

    private static func normalizedBlock(_ inner: String) -> String? {
        let t = inner.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
