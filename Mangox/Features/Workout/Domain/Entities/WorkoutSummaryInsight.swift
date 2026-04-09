// Features/Workout/Domain/Entities/WorkoutSummaryInsight.swift
import Foundation

/// Pure domain entity: the on-device AI-generated insight for a completed workout.
/// Generation engine lives in Data/DataSources/WorkoutInsightGenerator.swift.
struct WorkoutSummaryOnDeviceInsight: Equatable, Sendable, Codable {
    let headline: String
    let bullets: [String]
    let caveat: String?
    /// Coach narrative paragraph (2-3 sentences). Nil for insights generated before Version 3.
    let narrative: String?

    var displayHeadline: String { AppFormat.naturalizeISODateSnippets(in: headline) }
    var displayBullets: [String] { bullets.map { AppFormat.naturalizeISODateSnippets(in: $0) } }
    var displayCaveat: String? { caveat.map { AppFormat.naturalizeISODateSnippets(in: $0) } }
    var displayNarrative: String? { narrative.map { AppFormat.naturalizeISODateSnippets(in: $0) } }
}
