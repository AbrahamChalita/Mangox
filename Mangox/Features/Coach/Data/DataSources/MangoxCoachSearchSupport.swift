import Foundation
import FoundationModels

// MARK: - Search intent heuristics

enum MangoxCoachSearchHeuristics {

    /// Live web / external articles — route through PCC web-search profile (Mangox cloud fallback).
    nonisolated static func prefersPCCWebSearch(for message: String) -> Bool {
        let lower = message.lowercased()
        let webKeywords = [
            "web search", "search the web", "search the internet", "look up online",
            "find an article", "find a study", "pubmed", "latest research",
            "what does the internet say", "news about",
            "can you search", "could you search", "please search", "search for",
            "look up", "find online",
        ]
        if webKeywords.contains(where: { lower.contains($0) }) { return true }
        // "search" + question without on-device Spotlight cues → live web.
        if lower.contains("search"),
            !prefersLocalSpotlightSearch(for: message),
            lower.contains("?") || lower.contains("what ") || lower.contains("when ")
                || lower.contains("next ") || lower.contains("upcoming")
        {
            return true
        }
        return false
    }

    /// On-device Spotlight / files — prefer coach tools (SpotlightSearchTool) before cloud.
    nonisolated static func prefersLocalSpotlightSearch(for message: String) -> Bool {
        let lower = message.lowercased()
        let localKeywords = [
            "find my note", "find my notes", "search my notes", "my documents",
            "on my phone", "on my device", "in my files", "in spotlight",
            "find that ride", "find the ride", "search my rides", "search my workouts",
            "something i saved", "something i wrote",
        ]
        return localKeywords.contains(where: { lower.contains($0) })
    }
}

// MARK: - PCC model factory (web-search extension when SDK exposes it)

@available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
enum MangoxPrivateCloudComputeModelFactory {

    /// Set to `true` once `PrivateCloudComputeLanguageModel.Extension.webSearch` ships in the public SDK.
    /// Verified absent from the iOS 27.0 SDK swiftinterface in Xcode beta (June 2026) — re-check each beta.
    nonisolated static let sdkExposesWebSearchExtension = false

    /// When false, web-search turns must use Mangox Cloud (PCC cannot ground live results yet).
    nonisolated static var isLiveWebSearchAvailable: Bool { sdkExposesWebSearchExtension }

    static func coachModel(enableWebSearch: Bool) -> PrivateCloudComputeLanguageModel {
        guard enableWebSearch, sdkExposesWebSearchExtension else {
            return PrivateCloudComputeLanguageModel()
        }
        // When Apple exposes the API in a future Xcode beta, enable:
        // return PrivateCloudComputeLanguageModel(
        //     extensions: [PrivateCloudComputeLanguageModel.Extension.webSearch(resultLocale: Locale.current)]
        // )
        return PrivateCloudComputeLanguageModel()
    }
}

// MARK: - Spotlight tool factory

enum MangoxCoachSpotlightToolFactory {
    static func makeSpotlightSearchTool() -> any Tool {
        MangoxSpotlightSearchTool()
    }
}

// MARK: - Transcript helpers

enum MangoxCoachTranscriptSearchSupport {

    /// Best-effort detection of Apple web-search segments in a PCC transcript.
    static func transcriptIndicatesWebSearch(_ session: LanguageModelSession) -> Bool {
        let joined = session.transcript.map { String(describing: $0) }.joined(separator: " ").lowercased()
        return joined.contains("websearch")
            || joined.contains("web_search")
            || joined.contains("web search")
    }

    /// Extracts URL references from a PCC / FM transcript after a web-search turn.
    static func referencesFromTranscript(_ session: LanguageModelSession) -> [ChatReference] {
        CoachReplyMetadataSupport.referencesFromTranscript(session)
    }
}
