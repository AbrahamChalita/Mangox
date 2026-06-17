import SwiftUI

/// Isolates all per-token stream reads in its own body so token updates re-render
/// only this subtree, never the full transcript.
struct CoachStreamingSection: View {
    @Environment(CoachViewModel.self) private var coachViewModel
    var bubbleMaxWidth: CGFloat = .infinity

    var body: some View {
        @Bindable var coach = coachViewModel

        if coach.isLoading {
            CoachPendingReplyBubble(
                streamingText: coach.streamDraftText,
                bubbleMaxWidth: bubbleMaxWidth,
                delivery: coach.streamDelivery,
                partialTags: coach.streamPartialTags,
                isSearchingWeb: coach.streamIsSearchingWeb,
                isThinking: coach.streamIsThinking,
                statusText: coach.streamStatusText,
                routeStatus: coach.streamRouteStatus
            )
            .id("pending-bubble")
        }
    }
}
