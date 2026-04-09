import Foundation

/// Display + outgoing copy for model-provided coach chips (fixes ugly `snake_case` labels).
enum CoachChipPresentation {
    static func displayTitle(for action: SuggestedAction) -> String {
        prettifyLabel(action.label, type: action.type)
    }

    /// Text sent as the user message when a chip is tapped.
    static func outgoingText(for action: SuggestedAction) -> String {
        prettifyLabel(action.label, type: action.type)
    }

    static func colorBucket(_ label: String) -> Int {
        var h: UInt32 = 5381
        for u in label.utf8 {
            h = ((h &<< 5) &+ h) &+ UInt32(u)
        }
        return Int(h % 3)
    }

    private static func prettifyLabel(_ raw: String, type: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return t }
        let typ = type.lowercased().replacingOccurrences(of: "-", with: "_")
        let norm = t.lowercased().replacingOccurrences(of: "-", with: "_")
        let slugChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        let isSlugToken =
            t.contains("_") && t.unicodeScalars.allSatisfy { slugChars.contains($0) }
        let matchesType = !typ.isEmpty && norm == typ
        if isSlugToken || matchesType {
            return titleCaseWords(t.replacingOccurrences(of: "_", with: " "))
        }
        if t.contains("_"), !t.contains(" "), !t.contains("."), !t.contains("?") {
            return titleCaseWords(t.replacingOccurrences(of: "_", with: " "))
        }
        return t
    }

    private static func titleCaseWords(_ s: String) -> String {
        s.split(whereSeparator: { $0.isWhitespace })
            .map { w in
                let word = String(w)
                guard let c = word.first else { return word }
                return String(c).uppercased() + word.dropFirst().lowercased()
            }
            .joined(separator: " ")
    }
}
