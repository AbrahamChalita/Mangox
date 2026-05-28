import SwiftUI

/// Self-contained coach transcript: message list, empty starters, streaming row, and scroll pinning.
/// Uses a single `VStack` subtree (no empty ↔ lazy branch swap) plus one debounced pin coordinator.
struct CoachChatTranscriptView: View {
    @Environment(CoachViewModel.self) private var coachViewModel

    let bubbleMaxWidth: CGFloat
    let greetingText: String
    let bottomSpacerHeight: CGFloat
    /// Increment from the composer when focus should re-pin the transcript above the keyboard.
    let composerFocusScrollNonce: Int
    let onSend: (String) -> Void
    let onPlanBuilder: () -> Void
    let onPaywall: () -> Void
    let onSuggestedAction: (SuggestedAction) -> Void
    let onRetry: () -> Void

    @State private var viewportHeight: CGFloat = 0
    @State private var scrollPosition = ScrollPosition()
    @State private var stickToBottom = true
    @State private var pinTask: Task<Void, Never>?

    private static let bottomAnchorID = "coach-transcript-bottom"

    private var showEmptyState: Bool {
        coachViewModel.messages.isEmpty && !coachViewModel.isLoading
    }

    private var contentAlignment: Alignment {
        showEmptyState ? .center : .bottom
    }

    private var startersLoading: Bool {
        showEmptyState && coachViewModel.starterContent == nil
    }

    private var latestAssistantMessageID: UUID? {
        coachViewModel.messages.last { $0.role == .assistant }?.id
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                if showEmptyState {
                    emptyState
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                ForEach(coachViewModel.messages) { message in
                    CoachMessageRow(
                        message: message,
                        isLatestAssistant: message.role == .assistant
                            && message.id == latestAssistantMessageID,
                        bubbleMaxWidth: bubbleMaxWidth,
                        suggestionsInteractive: !coachViewModel.isLoading,
                        onRetry: onRetry,
                        onSuggestedAction: onSuggestedAction,
                        onFollowUpBatchComplete: onSend
                    )
                }

                if coachViewModel.generatingPlan && !coachViewModel.isLoading {
                    CoachStreamStatusRow(
                        text: coachViewModel.planProgress?.message ?? "Building your plan…",
                        style: .cloud
                    )
                    .id("planGen")
                }

                CoachStreamingSection()

                Color.clear
                    .frame(height: bottomSpacerHeight)

                Color.clear
                    .frame(height: 1)
                    .id(Self.bottomAnchorID)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, showEmptyState ? 0 : 12)
            .padding(.bottom, 16)
            .scrollTargetLayout()
            .frame(
                maxWidth: .infinity,
                minHeight: max(viewportHeight, 1),
                alignment: contentAlignment
            )
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { viewportHeight = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, newValue in
                        viewportHeight = newValue
                    }
            }
        }
        .defaultScrollAnchor(.bottom)
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
        .scrollPosition($scrollPosition)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            let visibleBottom = geometry.contentOffset.y + geometry.containerSize.height
            let contentBottom = geometry.contentSize.height
            return contentBottom - visibleBottom <= 80
        } action: { _, isNearBottom in
            if isNearBottom {
                stickToBottom = true
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    guard abs(value.translation.height) > abs(value.translation.width) else { return }
                    stickToBottom = false
                }
        )
        .onAppear {
            if !coachViewModel.messages.isEmpty || coachViewModel.isLoading {
                schedulePinToBottom(animated: false)
            }
        }
        .onChange(of: viewportHeight) { _, height in
            guard height > 0, stickToBottom else { return }
            schedulePinToBottom(animated: false)
        }
        .onChange(of: coachViewModel.messages.count) { oldCount, newCount in
            guard newCount > oldCount else { return }
            stickToBottom = true
            schedulePinToBottom(animated: true)
        }
        .onChange(of: coachViewModel.isLoading) { _, loading in
            if loading {
                stickToBottom = true
                schedulePinToBottom(animated: false)
            } else {
                schedulePinToBottom(animated: true)
            }
        }
        .onChange(of: coachViewModel.streamDraftText) { _, newValue in
            guard stickToBottom, !newValue.isEmpty else { return }
            schedulePinToBottom(animated: false, debounceMs: 180)
        }
        .onChange(of: coachViewModel.generatingPlan) { _, generating in
            if generating { schedulePinToBottom(animated: true) }
        }
        .onChange(of: coachViewModel.planConfirmationDraft?.id) { _, _ in
            schedulePinToBottom(animated: true)
        }
        .onChange(of: coachViewModel.planSaveCelebration?.planID) { _, _ in
            schedulePinToBottom(animated: true)
        }
        .onChange(of: coachViewModel.workoutConfirmationDraft?.id) { _, _ in
            schedulePinToBottom(animated: true)
        }
        .onChange(of: coachViewModel.workoutSaveCelebration?.id) { _, _ in
            schedulePinToBottom(animated: true)
        }
        .onChange(of: composerFocusScrollNonce) { _, _ in
            guard !coachViewModel.messages.isEmpty else { return }
            stickToBottom = true
            schedulePinToBottom(animated: true)
        }
    }

    // MARK: - Empty state

    @ViewBuilder
    private var emptyState: some View {
        if startersLoading {
            starterLoadingState
        } else {
            let content =
                coachViewModel.starterContent
                ?? CoachEmptyStartersContent(
                    prompts: coachViewModel.contextualQuickPrompts(),
                    topicTags: []
                )

            VStack(spacing: 0) {
                CoachEmptyStartersPanel(
                    bubbleMaxWidth: bubbleMaxWidth,
                    greetingTitle: greetingText,
                    headline: "What should we work on?",
                    subhead:
                        "Ask about training, recovery, or build a plan. Starters only appear when Mangox has data to support them.",
                    topicTags: content.topicTags,
                    prompts: content.prompts,
                    onPlanBuilder: onPlanBuilder,
                    onPrompt: { onSend($0.text) }
                )
                .frame(maxWidth: bubbleMaxWidth)

                if coachViewModel.hasReachedFreeLimit(isPro: coachViewModel.isPro) {
                    dailyLimitCard
                        .padding(.top, 22)
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

    private var dailyLimitCard: some View {
        VStack(spacing: 12) {
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
        .padding(18)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AppColor.mango.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Scroll pinning

    /// Debounced scroll-to-bottom so layout finishes before we anchor (fixes first-message stuck-at-top).
    private func schedulePinToBottom(animated: Bool = false, debounceMs: UInt64 = 0) {
        guard stickToBottom else { return }
        pinTask?.cancel()
        pinTask = Task { @MainActor in
            if debounceMs > 0 {
                try? await Task.sleep(nanoseconds: debounceMs * 1_000_000)
            }
            guard !Task.isCancelled, stickToBottom else { return }
            await Task.yield()
            guard !Task.isCancelled, stickToBottom else { return }

            let pin = {
                scrollPosition.scrollTo(id: Self.bottomAnchorID, anchor: .bottom)
            }
            if animated {
                withAnimation(MangoxMotion.snappy, pin)
            } else {
                pin()
            }
        }
    }

}
