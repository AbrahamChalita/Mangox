import SwiftUI

/// Self-contained coach transcript: message list, empty starters, and streaming row.
/// Streaming stick-to-bottom is delegated to `defaultScrollAnchor(.bottom, for: .sizeChanges)` so
/// per-token updates never invalidate this view; explicit pins only fire on discrete events
/// (send, appear, composer focus, plan banners).
struct CoachChatTranscriptView: View {
    @Environment(CoachViewModel.self) private var coachViewModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let bubbleMaxWidth: CGFloat
    let greetingText: String
    let bottomSpacerHeight: CGFloat
    /// Increment from the composer when focus should re-pin the transcript above the keyboard.
    let composerFocusScrollNonce: Int
    var sentChipKey: String? = nil
    let onSend: (String) -> Void
    let onPlanBuilder: () -> Void
    let onPaywall: () -> Void
    let onSuggestedAction: (UUID, SuggestedAction) -> Void
    let onRetry: () -> Void
    let onRetryCloud: () -> Void
    let onFeedback: (UUID, Int) -> Void

    @State private var scrollPosition = ScrollPosition()
    @State private var pinTask: Task<Void, Never>?
    @State private var isScrolledAwayFromBottom = false
    @State private var isDailyLimitCardDismissed = false

    private static let bottomAnchorID = "coach-transcript-bottom"
    private static let bottomScrollThreshold: CGFloat = 80

    var body: some View {
        @Bindable var coach = coachViewModel

        let showEmptyState = coach.messages.isEmpty && !coach.isLoading
        let startersLoading = showEmptyState && coach.starterContent == nil
        let latestAssistantMessageID = coach.messages.last { $0.role == .assistant }?.id
        let messages = coach.messages
        let showTimestampByID = timestampVisibility(for: messages)

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if showEmptyState {
                    emptyState(
                        coach: coach,
                        startersLoading: startersLoading
                    )
                        .frame(maxWidth: .infinity)
                        .transition(emptyStateTransition)
                }

                let latestAssistantID = latestAssistantMessageID
                ForEach(messages) { message in
                    CoachMessageRowEquatableContainer(
                        message: message,
                        isLatestAssistant: message.role == .assistant
                            && message.id == latestAssistantID,
                        bubbleMaxWidth: bubbleMaxWidth,
                        suggestionsInteractive: message.id == latestAssistantID
                            ? !coach.isLoading
                            : true,
                        sentChipKey: sentChipKey,
                        showTimestamp: showTimestampByID[message.id] ?? false,
                        onRetry: onRetry,
                        onRetryCloud: onRetryCloud,
                        onFeedback: { onFeedback(message.id, $0) },
                        onSuggestedAction: { onSuggestedAction(message.id, $0) },
                        onFollowUpBatchComplete: onSend
                    )
                    .equatable()
                }

                CoachPlanGenerationStatusSection()

                CoachStreamingSection(bubbleMaxWidth: bubbleMaxWidth)

                Color.clear
                    .frame(height: bottomSpacerHeight)

                Color.clear
                    .frame(height: 1)
                    .id(Self.bottomAnchorID)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .scrollTargetLayout()
        }
        // The system keeps the transcript pinned while streamed content grows, and stops
        // following as soon as the user scrolls away — no manual offset bookkeeping.
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .scrollBounceBehavior(.always, axes: .vertical)
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
        .scrollPosition($scrollPosition)
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            // Distance from the bottom edge of the visible rect to the bottom of the content.
            let bottomEdge = geo.contentOffset.y + geo.visibleRect.height
            return max(0, geo.contentSize.height - bottomEdge)
        } action: { _, distanceToBottom in
            let away = distanceToBottom > Self.bottomScrollThreshold
            if away != isScrolledAwayFromBottom {
                isScrolledAwayFromBottom = away
            }
        }
        .onAppear {
            if !coach.messages.isEmpty || coach.isLoading {
                schedulePinToBottom(animated: false)
            }
        }
        .onChange(of: coach.messages.count) { oldCount, newCount in
            guard newCount > oldCount else { return }
            // Only force-pin for outgoing user messages; incoming coach replies rely on
            // defaultScrollAnchor(.bottom, for: .sizeChanges) so reading history isn't jerked.
            let isOutgoing = coach.messages.last?.role == .user
            guard isOutgoing else { return }
            schedulePinToBottom(animated: false)
        }
        .onChange(of: coach.planSaveCelebration?.planID) { _, _ in
            schedulePinToBottom(animated: true)
        }
        .onChange(of: coach.workoutConfirmationDraft?.id) { _, _ in
            schedulePinToBottom(animated: true)
        }
        .onChange(of: coach.workoutSaveCelebration?.id) { _, _ in
            schedulePinToBottom(animated: true)
        }
        .onChange(of: composerFocusScrollNonce) { _, _ in
            guard !coach.messages.isEmpty else { return }
            schedulePinToBottom(animated: true)
        }
        .onChange(of: showEmptyState) { _, isEmpty in
            if isEmpty {
                isDailyLimitCardDismissed = false
            }
        }
        .animation(
            CoachChatMotionSupport.animation(reduceMotion: accessibilityReduceMotion, MangoxMotion.smooth),
            value: showEmptyState
        )
        .overlay(alignment: .bottomTrailing) {
            if isScrolledAwayFromBottom {
                Button {
                    HapticManager.shared.coachQuickReplyTapped()
                    schedulePinToBottom(animated: true)
                } label: {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(AppColor.mango)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Scroll to latest message")
                .padding(.trailing, 20)
                .padding(.bottom, 12)
                .transition(
                    accessibilityReduceMotion
                        ? .opacity
                        : .move(edge: .bottom).combined(with: .opacity)
                )
            }
        }
    }

    /// Computes timestamp visibility once per render instead of scanning the array
    /// for every message (was O(n²) for long transcripts).
    private func timestampVisibility(for messages: [ChatMessage]) -> [UUID: Bool] {
        var result: [UUID: Bool] = [:]
        result.reserveCapacity(messages.count)
        for index in messages.indices {
            let message = messages[index]
            let previousTimestamp = index > 0 ? messages[index - 1].timestamp : nil
            result[message.id] = CoachMessageTimestampFormatting.shouldShow(
                previousTimestamp: previousTimestamp,
                current: message.timestamp
            )
        }
        return result
    }

    private var emptyStateTransition: AnyTransition {
        if accessibilityReduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .opacity,
            removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .topLeading))
        )
    }

    // MARK: - Empty state

    @ViewBuilder
    private func emptyState(
        coach: CoachViewModel,
        startersLoading: Bool
    ) -> some View {
        if startersLoading {
            starterLoadingState
        } else {
            let content =
                coach.starterContent
                ?? CoachEmptyStartersContent(
                    prompts: coach.contextualQuickPrompts(),
                    topicTags: []
                )

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    CoachEmptyStartersPanel(
                        bubbleMaxWidth: bubbleMaxWidth,
                        greetingTitle: greetingText,
                        headline: "What should we work on?",
                        subhead:
                            "Ask about training, recovery, or build a plan. Starters only appear when Mangox has data to support them.",
                        topicTags: content.topicTags,
                        prompts: content.prompts,
                        startersEnabled: !coach.isLoading,
                        onPlanBuilder: onPlanBuilder,
                        onPrompt: { onSend($0.text) }
                    )
                    .frame(maxWidth: bubbleMaxWidth)
                    Spacer(minLength: 0)
                }

                if coach.hasReachedFreeLimit(isPro: coach.isPro), !isDailyLimitCardDismissed {
                    dailyLimitCard { isDailyLimitCardDismissed = true }
                        .padding(.top, 22)
                        .frame(maxWidth: bubbleMaxWidth)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 2)
            .padding(.top, 28)
            .padding(.bottom, 16)
        }
    }

    private var starterLoadingState: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ProgressView()
                    .tint(AppColor.mango)
                Text("Preparing grounded starters…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }

            MangoxChatBubbleSkeleton(isUser: false)
            MangoxChatBubbleSkeleton(isUser: false)
        }
        .frame(maxWidth: bubbleMaxWidth, alignment: .leading)
        .padding(.horizontal, 2)
        .padding(.vertical, 16)
    }

    private func dailyLimitCard(onDismiss: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            HStack {
                Spacer(minLength: 0)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.35))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss limit notice")
            }

            Text("Daily limit reached")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            Text("Pro unlocks unlimited coach messages.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
            Button(action: onPaywall) {
                Text("Upgrade")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.8))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppColor.mango)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(MangoxPressStyle())
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(AppColor.mango.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Scroll pinning

    /// One-shot scroll-to-bottom for discrete events (send, appear, plan banners). Yields once so
    /// layout finishes before anchoring (fixes first-message stuck-at-top).
    private func schedulePinToBottom(animated: Bool = false) {
        isScrolledAwayFromBottom = false
        pinTask?.cancel()
        pinTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }

            let pin = {
                scrollPosition.scrollTo(id: Self.bottomAnchorID, anchor: .bottom)
            }
            if animated {
                withAnimation(
                    CoachChatMotionSupport.animation(reduceMotion: accessibilityReduceMotion, MangoxMotion.snappy),
                    pin
                )
            } else {
                pin()
            }
        }
    }

}

/// Isolated from the message list so `planProgress` ticks do not re-layout committed bubbles.
private struct CoachPlanGenerationStatusSection: View {
    @Environment(CoachViewModel.self) private var coachViewModel

    var body: some View {
        @Bindable var coach = coachViewModel

        if coach.generatingPlan && !coach.isLoading {
            CoachStreamStatusRow(
                text: coach.planProgress?.message ?? "Building your plan…",
                style: .cloud
            )
            .id("planGen")
        }
    }
}

/// Skips body recomputation when unrelated transcript state changes (e.g. plan progress).
private struct CoachMessageRowEquatableContainer: View, Equatable {
    let message: ChatMessage
    let isLatestAssistant: Bool
    let bubbleMaxWidth: CGFloat
    let suggestionsInteractive: Bool
    let sentChipKey: String?
    let showTimestamp: Bool
    let onRetry: () -> Void
    let onRetryCloud: () -> Void
    let onFeedback: (Int) -> Void
    let onSuggestedAction: (SuggestedAction) -> Void
    let onFollowUpBatchComplete: (String) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.message == rhs.message
            && lhs.isLatestAssistant == rhs.isLatestAssistant
            && lhs.bubbleMaxWidth == rhs.bubbleMaxWidth
            && lhs.suggestionsInteractive == rhs.suggestionsInteractive
            && lhs.sentChipKey == rhs.sentChipKey
            && lhs.showTimestamp == rhs.showTimestamp
    }

    var body: some View {
        CoachMessageRow(
            message: message,
            isLatestAssistant: isLatestAssistant,
            bubbleMaxWidth: bubbleMaxWidth,
            suggestionsInteractive: suggestionsInteractive,
            sentChipKey: sentChipKey,
            showTimestamp: showTimestamp,
            onRetry: onRetry,
            onRetryCloud: onRetryCloud,
            onFeedback: onFeedback,
            onSuggestedAction: onSuggestedAction,
            onFollowUpBatchComplete: onFollowUpBatchComplete
        )
    }
}

// MARK: - Context window banner

struct CoachContextWindowBanner: View {
    let currentCount: Int
    let windowSize: Int
    let onStartFresh: () -> Void
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "text.bubble")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColor.yellow.opacity(0.9))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text("Context \(currentCount)/\(windowSize)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                Text("Older turns are summarized. Start a new chat for sharper follow-ups.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.42))
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onStartFresh) {
                    Text("New chat")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppColor.mango)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }

            Spacer(minLength: 0)

                if let onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.35))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss")
                }
        }
        .padding(12)
        .mangoxSurface(
            .flatCustom(fill: Color.white.opacity(0.04), border: AppColor.yellow.opacity(0.2)),
            shape: .rounded(MangoxRadius.sharp.rawValue)
        )
    }
}
