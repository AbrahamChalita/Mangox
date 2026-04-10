// Features/Coach/Domain/Entities/CoachStarterContent.swift
import Foundation

struct QuickPrompt: Identifiable, Equatable, Sendable {
    var id: String { text }
    let text: String
    let icon: String
}

/// Empty-state quick starters plus optional content-tagging topic chips (Foundation Models).
struct CoachEmptyStartersContent: Equatable, Sendable {
    let prompts: [QuickPrompt]
    let topicTags: [String]
}
