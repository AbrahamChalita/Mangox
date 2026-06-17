import SwiftData
import SwiftUI
import UIKit

enum CoachAuxiliarySheet: String, Identifiable {
    case paywall, plans, workouts
    var id: String { rawValue }
}

private enum CoachChatColumnWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 400
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Primary coach chat surface: streaming replies and plan-builder entry.
/// Avoids a root `GeometryReader` so the system keyboard safe area correctly lifts the transcript.
struct CoachConversationView: View {
    @Environment(CoachViewModel.self) private var coachViewModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    @Binding var navigationPath: NavigationPath
    /// When chat is presented from `CoachTabRootView`, toggling this dismisses the cover (e.g. Close, or after opening a plan).
    @Binding var chatSheetPresented: Bool

    @State private var auxiliarySheet: CoachAuxiliarySheet?
    /// Pushed (not `.sheet`) so it isn’t torn down by the paywall/plans `item` sheet or full-screen chat cover.
    @State private var showConversationsList = false
    @State private var chatColumnWidth: CGFloat = 400
    @State private var composerFocusScrollNonce = 0
    @State private var sentChipKey: String?
    @State private var contextBannerDismissed = false

    private static let planBuilderSeed =
        "I want to build a structured training plan for an event. Ask me about my goal, target date, weekly training hours, and experience, then outline next steps."

    private let greetingText: String = {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }()

    private static func bubbleMaxWidth(containerWidth: CGFloat) -> CGFloat {
        let horizontalPadding: CGFloat = 32
        // Geometry/preference can report 0 briefly; a near-zero max width makes LazyVStack relayout wildly.
        let w = max(containerWidth, 64)
        return min(580, max(120, w - horizontalPadding))
    }

    // MARK: - Extracted Components

    @ViewBuilder
    private var coachBackgroundView: some View {
        ZStack {
            AppColor.bg
            OptimizedRadialGradient()
        }
        .ignoresSafeArea()
        .mangoxGridBackground(opacity: 0.35)
    }

    private struct OptimizedRadialGradient: View {
        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            let mangoOpacity = colorScheme == .dark ? 0.08 : 0.07
            let blueOpacity = colorScheme == .dark ? 0.05 : 0.06

            RadialGradient(
                colors: [AppColor.mango.opacity(mangoOpacity), Color.clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 420
            )
            .blur(radius: 0.5)

            RadialGradient(
                colors: [Color.blue.opacity(blueOpacity), Color.clear],
                center: .bottomLeading,
                startRadius: 10,
                endRadius: 380
            )
            .blur(radius: 0.5)
        }
    }

    // MARK: - Reusable Components

    private struct CoachMetricsStrip: View {
        let isPro: Bool
        let bypassesDailyLimit: Bool
        let remainingFreeMessages: Int

        var body: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    metricCapsule(
                        icon: "bolt.fill", label: "FTP", value: "\(PowerZone.ftp)W",
                        color: AppColor.yellow)
                    metricCapsule(
                        icon: "heart.fill", label: "Max HR", value: "\(HeartRateZone.maxHR)",
                        color: AppColor.heartRate)
                    if !isPro {
                        if bypassesDailyLimit {
                            metricCapsule(
                                icon: "person.fill.checkmark",
                                label: "Coach",
                                value: "Staff",
                                color: AppColor.mango.opacity(0.85)
                            )
                        } else {
                            metricCapsule(
                                icon: "cloud.fill",
                                label: "Cloud",
                                value: remainingFreeMessages > 0 ? "\(remainingFreeMessages) left" : "limit",
                                color: remainingFreeMessages > 0 ? AppColor.fg2 : AppColor.red
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(AppColor.hair)
                    .frame(height: 1)
            }
        }

        private func metricCapsule(icon: String, label: String, value: String, color: Color)
            -> some View
        {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(color)
                Text(label.uppercased())
                    .mangoxFont(.micro)
                    .foregroundStyle(AppColor.fg3)
                    .tracking(0.6)
                Text(value)
                    .font(MangoxFont.caption.value)
                    .foregroundStyle(AppColor.fg1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .mangoxSurface(.flat, shape: .rounded(MangoxRadius.sharp.rawValue))
        }
    }

    @ViewBuilder
    private func topChromeView(coach: CoachViewModel) -> some View {
        ZStack {
            HStack(spacing: 0) {
                Button {
                    chatSheetPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppColor.fg2)
                        .frame(width: 44, height: 44)
                        .mangoxSurface(.flat, shape: .rounded(MangoxRadius.sharp.rawValue))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(A11yL10n.closeChat)

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    Button {
                        showConversationsList = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 44, height: 44)
                            .mangoxSurface(.flat, shape: .rounded(MangoxRadius.sharp.rawValue))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColor.fg2)
                    .accessibilityLabel(A11yL10n.conversations)

                    Button {
                        coach.createNewSession()
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 44, height: 44)
                            .mangoxSurface(.flat, shape: .rounded(MangoxRadius.sharp.rawValue))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColor.fg2)
                    .accessibilityLabel(A11yL10n.newConversation)
                    .disabled(coach.isLoading)
                }
            }
            .padding(.horizontal, 8)

            VStack(spacing: 2) {
                Text("COACH")
                    .mangoxFont(.label)
                    .foregroundStyle(AppColor.mango)
                    .tracking(1.4)
                Text(greetingText)
                    .font(MangoxFont.caption.value)
                    .foregroundStyle(AppColor.fg2)
            }
                .accessibilityAddTraits(.isHeader)
                .allowsHitTesting(false)
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColor.hair)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func metricsStripView(coach: CoachViewModel) -> some View {
        CoachMetricsStrip(
            isPro: coach.isPro,
            bypassesDailyLimit: coach.bypassesDailyLimit,
            remainingFreeMessages: coach.remainingFreeMessages(isPro: coach.isPro)
        )
    }

    @ViewBuilder
    private func contextBannerView(
        coach: CoachViewModel,
        suggestsFreshConversation: Bool
    ) -> some View {
        if suggestsFreshConversation,
            !coach.isLoading,
            !contextBannerDismissed
        {
            CoachContextWindowBanner(
                currentCount: coach.currentContextCount,
                windowSize: coach.contextWindowSize,
                onStartFresh: { coach.createNewSession() },
                onDismiss: { contextBannerDismissed = true }
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .transition(
                accessibilityReduceMotion
                    ? .opacity
                    : .move(edge: .top).combined(with: .opacity)
            )
            .animation(
                accessibilityReduceMotion ? .easeInOut(duration: 0.16) : .smooth(duration: 0.24),
                value: suggestsFreshConversation
            )
        }
    }

    @ViewBuilder
    private func inputBarView(
        coach: CoachViewModel,
        showComposerLimitBanner: Bool
    ) -> some View {
        CoachInputBarWrapper(
            navigationPath: $navigationPath,
            chatSheetPresented: $chatSheetPresented,
            auxiliarySheet: $auxiliarySheet,
            showComposerLimitBanner: showComposerLimitBanner,
            onPlanBuilder: { send(Self.planBuilderSeed, forcePlanIntake: true, coach: coach) },
            sendAction: { text, image in send(text, image: image, coach: coach) },
            onFocusChanged: { focused in
                if focused && !coach.messages.isEmpty {
                    composerFocusScrollNonce += 1
                }
            }
        )
        .animation(
            accessibilityReduceMotion ? .easeInOut(duration: 0.16) : .smooth(duration: 0.28),
            value: showComposerLimitBanner
        )
    }

    var body: some View {
        @Bindable var coach = coachViewModel

        let showComposerLimitBanner =
            coach.hasReachedFreeLimit(isPro: coach.isPro) && !coach.messages.isEmpty
        let suggestsFreshConversation = coach.suggestsFreshConversation
        let transcriptBottomSpacer = coachTranscriptBottomSpacerHeight(for: coach)
        let starterTaskID = coach.currentSessionID?.uuidString ?? "none"

        ZStack {
            coachBackgroundView
            VStack(spacing: 0) {
                topChromeView(coach: coach)
                metricsStripView(coach: coach)
                contextBannerView(
                    coach: coach,
                    suggestsFreshConversation: suggestsFreshConversation
                )
                CoachChatTranscriptView(
                    bubbleMaxWidth: Self.bubbleMaxWidth(containerWidth: chatColumnWidth),
                    greetingText: greetingText,
                    bottomSpacerHeight: transcriptBottomSpacer,
                    composerFocusScrollNonce: composerFocusScrollNonce,
                    sentChipKey: sentChipKey,
                    onSend: { send($0, coach: coach) },
                    onPlanBuilder: { send(Self.planBuilderSeed, forcePlanIntake: true, coach: coach) },
                    onPaywall: { auxiliarySheet = .paywall },
                    onSuggestedAction: { messageID, action in
                        handleSuggestedAction(from: messageID, action, coach: coach)
                    },
                    onRetry: {
                        guard coach.canBeginTurn() else { return }
                        HapticManager.shared.coachMessageSent()
                        Task { @MainActor in
                            await coach.retryLastUserMessage(isPro: coach.isPro)
                        }
                    },
                    onRetryCloud: {
                        guard coach.canBeginTurn() else { return }
                        HapticManager.shared.coachMessageSent()
                        Task { @MainActor in
                            await coach.regenerateLastMessagePreferringCloud(isPro: coach.isPro)
                        }
                    },
                    onFeedback: { messageID, score in
                        coach.submitFeedback(for: messageID, score: score)
                    }
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: CoachChatColumnWidthKey.self, value: proxy.size.width)
                }
            }
            .onPreferenceChange(CoachChatColumnWidthKey.self) { newValue in
                let clampedWidth = max(newValue, 64)
                guard abs(clampedWidth - chatColumnWidth) > 0.5 else { return }
                chatColumnWidth = clampedWidth
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                inputBarView(
                    coach: coach,
                    showComposerLimitBanner: showComposerLimitBanner
                )
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showConversationsList) {
            CoachSessionsSheet()
        }
        .sheet(item: $auxiliarySheet) { sheet in
            switch sheet {
            case .paywall:
                PaywallView(viewModel: PaywallViewModel(purchasesService: PurchasesManager.shared))
            case .plans:
                CoachPlansSheet(
                    navigationPath: $navigationPath, dismissParentChat: $chatSheetPresented)
            case .workouts:
                CoachWorkoutsSheet(
                    navigationPath: $navigationPath, dismissParentChat: $chatSheetPresented)
            }
        }
        .task {
            OnDeviceCoachEngine.prewarmNarrowCoachIfAvailable()
            OnDeviceCoachEngine.prewarmPCCCoachIfAvailable()
            await coach.warmCoachContextCache()
            await coach.loadPersistedMessagesIfNeeded()
        }
        .task(id: starterTaskID) {
            await coach.refreshStarterContentIfNeeded()
        }
        .onChange(of: coach.isLoading) { _, loading in
            if !loading {
                sentChipKey = nil
            }
        }
        .onChange(of: coach.error) { _, error in
            if error != nil, !coach.isLoading {
                sentChipKey = nil
            }
        }
        .onChange(of: coach.currentSessionID) { _, _ in
            contextBannerDismissed = false
        }
    }

    /// Extra lift so the last coach bubble clears the plan card; smaller spacer when the inset is tall.
    private func coachTranscriptBottomSpacerHeight(for coach: CoachViewModel) -> CGFloat {
        let coachPlanSheetActive =
            coach.planConfirmationDraft != nil
            || coach.planSaveCelebration != nil
            || coach.workoutConfirmationDraft != nil
            || coach.workoutSaveCelebration != nil
        if coachPlanSheetActive { return 44 }
        return 28
    }

    // MARK: - Actions

    @discardableResult
    private func send(
        _ text: String,
        forcePlanIntake: Bool = false,
        image: CoachUserImageAttachment? = nil,
        coach: CoachViewModel
    ) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || image != nil else { return false }
        let planIntake = forcePlanIntake || AIService.shouldForcePlanIntake(for: trimmed)
        guard coach.canSendCoachMessage(
            trimmed,
            isPro: coach.isPro,
            forcePlanIntake: planIntake,
            hasImage: image != nil
        ) else {
            auxiliarySheet = .paywall
            return false
        }
        // Take a synchronous reservation so two rapid taps cannot both pass the loading
        // check before the first Task body runs. The reservation is consumed by
        // `sendMessage` when its Task begins.
        guard coach.canBeginTurn() else { return false }
        HapticManager.shared.coachMessageSent()
        Task { @MainActor in
            await coach.sendMessage(
                trimmed,
                isPro: coach.isPro,
                forcePlanIntake: planIntake,
                image: image
            )
        }
        return true
    }

    /// Taps on model-provided `suggestedActions` chips (same JSON contract as the Mangox Cloud coach).
    private func handleSuggestedAction(
        from messageID: UUID,
        _ action: SuggestedAction,
        coach: CoachViewModel
    ) {
        let kind = action.type.lowercased()
        switch kind {
        case "retry":
            guard coach.canBeginTurn() else { return }
            HapticManager.shared.coachQuickReplyTapped()
            Task { @MainActor in
                await coach.retryLastUserMessage(isPro: coach.isPro)
            }
            return
        case "escalate_cloud":
            guard coach.canBeginTurn() else { return }
            HapticManager.shared.coachQuickReplyTapped()
            Task { @MainActor in
                await coach.regenerateLastMessagePreferringCloud(isPro: coach.isPro)
            }
            return
        case "navigate_to_plan":
            HapticManager.shared.coachQuickReplyTapped()
            auxiliarySheet = .plans
        case "navigate_to_my_plans", "open_my_plans":
            HapticManager.shared.coachQuickReplyTapped()
            auxiliarySheet = .plans
        case "navigate_to_my_workouts", "open_my_workouts":
            HapticManager.shared.coachQuickReplyTapped()
            auxiliarySheet = .workouts
        case "start_workout":
            guard let celebration = coach.workoutSaveCelebration else { return }
            HapticManager.shared.coachQuickReplyTapped()
            navigationPath.append(AppRoute.customWorkoutRide(templateID: celebration.templateID))
            coach.clearWorkoutSaveCelebration()
            chatSheetPresented = false
        default:
            let outgoing = CoachChipPresentation.outgoingText(for: action)
            guard coach.canSendCoachMessage(
                outgoing,
                isPro: coach.isPro,
                forcePlanIntake: AIService.shouldForcePlanIntake(for: outgoing)
            ) else {
                auxiliarySheet = .paywall
                return
            }
            HapticManager.shared.coachQuickReplyTapped()
            sentChipKey = CoachChipSentState.key(messageID: messageID, action: action)
            send(outgoing, forcePlanIntake: AIService.shouldForcePlanIntake(for: outgoing), coach: coach)
        }
    }
}

