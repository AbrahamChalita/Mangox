// Features/Workout/Data/DataSources/WorkoutHistoryKeywordRetriever.swift
import Foundation
import SwiftData

/// Lightweight on-device “RAG” before true embeddings: token overlap over recent ride text.
enum WorkoutHistoryKeywordRetriever {
    private static let stopwords: Set<String> = [
        "the", "and", "for", "with", "this", "that", "from", "have", "has", "was", "were", "are",
        "you", "your", "how", "what", "when", "did", "does", "about", "into", "any", "can", "could",
        "would", "should", "ride", "rides", "workout", "workouts", "last", "my", "me", "week", "day",
    ]

    /// Appends only when the query has signal and at least one workout line scores.
    static func appendixIfRelevant(userMessage: String, modelContext: ModelContext) -> String? {
        let tokens = queryTokens(from: userMessage)
        guard tokens.count >= 2 else { return nil }

        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { $0.statusRaw == "completed" },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        let rides = ((try? modelContext.fetch(descriptor)) ?? []).filter(\.isValid).prefix(72)

        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none

        var scored: [(Int, String)] = []
        for ride in rides {
            var line =
                "\(df.string(from: ride.startDate)): TSS \(Int(ride.tss)), \(Int(ride.duration / 60))min"
            if ride.avgPower > 0 {
                line += ", \(Int(ride.avgPower))W avg"
            }
            if !ride.notes.isEmpty {
                line += " — \(ride.notes.prefix(160))"
            }
            if let r = ride.savedRouteName, !r.isEmpty {
                line += " — route: \(r)"
            }
            let score = scoreLine(line, tokens: tokens)
            if score > 0 {
                scored.append((score, line))
            }
        }

        scored.sort { $0.0 > $1.0 }
        let top = scored.prefix(5).map(\.1)
        guard !top.isEmpty else { return nil }

        var out = "Keyword-matched rides (on-device search, not exhaustive):\n"
        out += top.joined(separator: "\n")
        if out.count > 1400 {
            return String(out.prefix(1400)) + "\n…"
        }
        return out
    }

    private static func queryTokens(from message: String) -> [String] {
        let lower = message.lowercased()
        var tokens: [String] = []
        var cur = ""
        for ch in lower {
            if ch.isLetter || ch.isNumber {
                cur.append(ch)
            } else if !cur.isEmpty {
                if cur.count >= 2, !stopwords.contains(cur) {
                    tokens.append(cur)
                }
                cur = ""
            }
        }
        if !cur.isEmpty, cur.count >= 2, !stopwords.contains(cur) {
            tokens.append(cur)
        }
        return tokens
    }

    private static func scoreLine(_ line: String, tokens: [String]) -> Int {
        let l = line.lowercased()
        var s = 0
        for t in tokens where l.contains(t) {
            s += t.count >= 4 ? 2 : 1
        }
        return s
    }
}
